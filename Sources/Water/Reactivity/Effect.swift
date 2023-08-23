//
//  Effect.swift
//  Water
//

// TODO: - global store watch effect
// TODO: - debugger display all effects with target

// MARK: - global Variables

var activeEffect: AnyEffect?

var shouldTrack: Bool = false
var canTrack: Bool {
    shouldTrack && activeEffect != nil
}

// MARK: - types

public typealias Scheduler = () -> Void
public typealias OnStop = () -> Void
public typealias AnyEffect = any Effectable
typealias AnyReactor = any Reactor

public protocol Effectable: AnyObject {
    associatedtype T
    
    @discardableResult
    func run(track: Bool) -> T
    func beforeRun() -> Bool
    func afterRun(_ lastShouldTrack: Bool)
    
    var scheduler: Scheduler? { get }
}
 
// MARK: - def

@discardableResult
public func defEffect<T>(_ effectClosure: @escaping () -> T, scheduler: Scheduler? = nil, onStop: OnStop? = nil) -> ReactiveEffectRunner<T> {
    let effect = ReactiveEffect(effectClosure, scheduler, onStop)
    effect.run(track: true)
    
    let runner = ReactiveEffectRunner(effect: effect)
    return runner
}

// MARK: - effect

public class ReactiveEffect<T>: Effectable {
    private let fn: () -> T
    
    public var scheduler: Scheduler?
    var onStop: OnStop?
    
    private var isActive = true
    private var parent: AnyEffect? = nil

    init(_ fn: @escaping () -> T, _ scheduler: Scheduler? = nil, _ onStop: OnStop? = nil) {
        self.fn = fn
        self.scheduler = scheduler
        self.onStop = onStop
    }

    deinit {
//        print("reactive effect deinit")
    }
    
    // TODO: - log track depth
    @discardableResult
    public func run(track: Bool = false) -> T {
        if !track {
            let lastShouldTrack = shouldTrack
            shouldTrack = false
            
            let res = fn()
            
            shouldTrack = lastShouldTrack
            return res
        }
        
        if !isActive {
            return fn()
        }

        let lastShouldTrack = beforeRun()
        let res = fn() // collect dependency effects
        afterRun(lastShouldTrack)

        return res
    }
    
    func stop(with target: AnyReactor? = nil) {
        if !isActive {
            return;
        }
        cleanupEffect(self, with: target)
        onStop?()
        isActive = false
    }
    
    // FIXME: - can reuse the code with not track
    public func beforeRun() -> Bool {
        let lastShouldTrack = shouldTrack
        parent = activeEffect
        activeEffect = self
        shouldTrack = true
        return lastShouldTrack
    }
    
    public func afterRun(_ lastShouldTrack: Bool) {
        activeEffect = parent
        shouldTrack = lastShouldTrack
        parent = nil
    }
}

// MARK: - runner and stop

public struct ReactiveEffectRunner<T> {
    let effect: ReactiveEffect<T>
    
    func run() -> T {
        effect.run(track: false)
    }
    
    func stop(with target: AnyReactor? = nil) {
        effect.stop(with: target)
    }
}

public func stop<T>(_ runner: ReactiveEffectRunner<T>) {
    runner.stop()
}

// MARK: - reactor

public func isDefined(_ value: Any) -> Bool {
    return value is Reactor
}

protocol Reactor: AnyObject {
    func trackEffects()
    func triggerEffects()
    func trackEffects(at keyPath: AnyKeyPath)
    func triggerEffects(at keyPath: AnyKeyPath)
}

// FIXME: - this default implements abstract from ReactiveObject, need reconsider
extension Reactor {
    func trackEffects() {
        track(reactor: self)
    }
    
    func triggerEffects() {
        trigger(reactor: self)
        // TODO: - need trigger watch effect
    }
    
    func trackEffects(at keyPath: AnyKeyPath) {
        track(reactor: self, at: keyPath)
    }
    
    func triggerEffects(at keyPath: AnyKeyPath) {
        trigger(reactor: self, at: keyPath)
        trigger(reactor: self) // also trigger the watch effect
    }
}

func trackEffects(_ effects: inout [AnyEffect]) {
    guard canTrack else {
        return
    }
    guard let currentEffect = activeEffect else {
        return
    }
    if effects.contains(where: { $0 === currentEffect }) {
        return
    }
    effects.append(currentEffect)
}

func triggerEffects(_ effects: [AnyEffect]) {
    for effect in effects {
        if let scheduler = effect.scheduler {
            scheduler()
        } else {
            effect.run(track: false)
        }
    }
}

// MARK: - track and trigger effect

struct ReactorEffectMap {
    let reactor: AnyReactor
    var effects: [AnyEffect] = []
}

struct ReactorKeyPathEffectMap {
    let reactor: AnyReactor
    let keyPath: AnyKeyPath
    var effects: [AnyEffect] = []
}

var globalEffects: [ReactorEffectMap] = []
var globalKeyPathEffects: [ReactorKeyPathEffectMap] = []

func track(reactor: AnyReactor) {
    var currentReactorMap: ReactorEffectMap
    
    let index = globalEffects.firstIndex { $0.reactor === reactor }
    if let index {
        currentReactorMap = globalEffects[index]
    } else {
        currentReactorMap = ReactorEffectMap(reactor: reactor)
    }
    
    var currentReactorEffects = currentReactorMap.effects
    trackEffects(&currentReactorEffects)
    
    currentReactorMap.effects = currentReactorEffects
    
    if let index {
        globalEffects[index] = currentReactorMap
    } else {
        globalEffects.append(currentReactorMap)
    }
}

func trigger(reactor: AnyReactor) {
    guard let currentReactorMap = globalEffects.filter({ $0.reactor === reactor }).first else {
        return
    }
    let currentReactorEffects = currentReactorMap.effects
    triggerEffects(currentReactorEffects)
}

func track(reactor: AnyReactor, at keyPath: AnyKeyPath) {
    var currentReactorKeyPathMap: ReactorKeyPathEffectMap
    
    let index = globalKeyPathEffects.firstIndex { $0.reactor === reactor && $0.keyPath === keyPath }
    if let index {
        currentReactorKeyPathMap = globalKeyPathEffects[index]
    } else {
        currentReactorKeyPathMap = ReactorKeyPathEffectMap(reactor: reactor, keyPath: keyPath)
    }
    
    var currentReactorKeyPathEffects = currentReactorKeyPathMap.effects
    trackEffects(&currentReactorKeyPathEffects)
    
    currentReactorKeyPathMap.effects = currentReactorKeyPathEffects
    
    if let index {
        globalKeyPathEffects[index] = currentReactorKeyPathMap
    } else {
        globalKeyPathEffects.append(currentReactorKeyPathMap)
    }
}

func trigger(reactor: AnyReactor, at keyPath: AnyKeyPath) {
    guard let currentTargetKeyPathMap = globalKeyPathEffects.filter({ $0.reactor === reactor && $0.keyPath === keyPath}).first else {
        return
    }
    let currentTargetKeyPathEffects = currentTargetKeyPathMap.effects
    triggerEffects(currentTargetKeyPathEffects)
}

func cleanupEffect(_ effect: AnyEffect, with target: AnyReactor? = nil) {
    if let target {
        if let index = globalEffects.firstIndex(where: {$0.reactor === target }) {
            cleanupGlobalEffects(effect: effect, at: index)
        } else if let index = globalKeyPathEffects.firstIndex(where: { $0.reactor === target }) {
            cleanupGlobalKeyPathEffects(effect: effect, at: index)
        }
    } else {
        // clean up from global target effects
        if let index = globalEffects.firstIndex(where: { $0.effects.contains{ $0 === effect} }) {
            cleanupGlobalEffects(effect: effect, at: index)
        }
        
        // clean up from global target keypath effects
        if let index = globalKeyPathEffects.firstIndex(where: { $0.effects.contains{ $0 === effect } }) {
            cleanupGlobalKeyPathEffects(effect: effect, at: index)
        }
    }
}

func cleanupGlobalEffects(effect: AnyEffect, at index: Int) {
    var reactorMap = globalEffects[index]
    var reactorEffects = reactorMap.effects
    reactorEffects.removeAll { $0 === effect }
    reactorMap.effects = reactorEffects
    globalEffects[index] = reactorMap
}

func cleanupGlobalKeyPathEffects(effect: AnyEffect, at index: Int) {
    var reactorKeyPathMap = globalKeyPathEffects[index]
    var reactorKeyPathEffects = reactorKeyPathMap.effects
    reactorKeyPathEffects.removeAll { $0 === effect }
    reactorKeyPathMap.effects = reactorKeyPathEffects
    globalKeyPathEffects[index] = reactorKeyPathMap
}
