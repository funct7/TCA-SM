import Foundation
import ComposableArchitecture

public protocol StateMachine : Reducer {
    associatedtype Input : Sendable
    associatedtype IOEffect : Sendable
    associatedtype IOResult : Sendable
    typealias IOResultStream = AsyncStream<IOResult>
    
    typealias Transition = (State?, ComposableEffect<IOEffect>)
    
    static func reduceInput(_ state: State, _ input: Input) -> Transition
    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition
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
