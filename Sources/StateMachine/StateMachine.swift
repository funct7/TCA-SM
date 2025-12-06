import Foundation
import ComposableArchitecture
import AsyncAlgorithms
import ConcurrencyExtras

public protocol StateMachine : Reducer {
    associatedtype Input : Sendable
    associatedtype IOEffect : Sendable
    associatedtype IOResult : Sendable
    typealias IOResultStream = AsyncStream<IOResult>
    
    typealias Transition = (State?, ComposableEffect<IOEffect>)
    
    static func reduceInput(_ state: State, _ input: Input) -> Transition
    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition
    /**
     - Warning: Do NOT handle the same ``IOEffect`` in both versions of ``StateMachine.runIOEffect(_:)`` since it will result in an undefined behavior.
     */
    func runIOEffect(_ ioEffect: IOEffect) async -> IOResult?
    /**
     - Warning: Do NOT handle the same ``IOEffect`` in both versions of ``StateMachine.runIOEffect(_:)`` since it will result in an undefined behavior.
     */
    func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream
}

public extension StateMachine {
    static var undefined: Transition { (nil, .none) }
    static var identity: Transition { (nil, .none) }
    static func nextState(_ state: State) -> Transition { (state, .none) }
    static func run(_ effect: IOEffect) -> Transition { (nil, .just(effect)) }
    static func run(_ effect: ComposableEffect<IOEffect>) -> Transition { (nil, effect) }
    static func transition(_ state: State, _ effect: IOEffect) -> Transition { (state, .just(effect)) }
    static func transition(_ state: State, _ effect: ComposableEffect<IOEffect>) -> Transition { (state, effect) }
    static func unsafe(_ action: @escaping () -> Void) -> Transition { action(); return (nil, .none) }
}

public extension StateMachine {
    
    func runIOEffect(_ ioEffect: IOEffect) async -> IOResult? { nil }
    
    func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream { IOResultStream.finished }
    
    func mergeIOResults(of ioEffect: IOEffect) -> IOResultStream {
        IOResultStream { continuation in
            let task = Task {
                let singleResultStream = IOResultStream { continuation in
                    let task = Task {
                        if let single = await runIOEffect(ioEffect) {
                            continuation.yield(single)
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
                
                for await value in merge(singleResultStream, runIOEffect(ioEffect)) {
                    continuation.yield(value)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
}
