import Foundation
import ComposableArchitecture

public protocol StateMachine {
    associatedtype State
    associatedtype Action
    associatedtype Input : Sendable
    associatedtype IOEffect : Sendable
    associatedtype IOResult : Sendable
    
    typealias Transition = (State?, IOEffect?)
    
    static func reduceInput(_ state: State, _ input: Input) -> Transition
    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition
    func runIOEffect(_ ioEffect: IOEffect) async -> IOResult?
}

public extension StateMachine {
    static var undefined: Transition { (nil, nil) }
    static var identity: Transition { (nil, nil) }
    static func nextState(_ state: State) -> Transition { (state, nil) }
    static func run(_ effect: IOEffect) -> Transition { (nil, effect) }
    static func transition(_ state: State, effect: IOEffect) -> Transition { (state, effect) }
    static func unsafe(_ action: @escaping () -> Void) -> Transition { action(); return (nil, nil) }
}
