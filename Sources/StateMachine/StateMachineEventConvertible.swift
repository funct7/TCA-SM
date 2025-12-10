import Foundation
import ComposableArchitecture

public protocol StateMachineEventConvertible<Input, IOResult> {
    associatedtype Input
    associatedtype IOResult
    
    static func input(_ value: Input) -> Self
    static func ioResult(_ value: IOResult) -> Self
    static func map(_ action: Self) -> StateMachineEvent<Input, IOResult>?
}

public extension StateMachine where
Action : StateMachineEventConvertible,
Action.Input == Input,
Action.IOResult == IOResult
{
    
    static func reduce(_ state: State, _ action: Action) -> Transition {
        return switch Action.map(action) {
        case nil: identity
        case .input(let input)?: reduceInput(state, input)
        case .ioResult(let ioResult)?: reduceIOResult(state, ioResult)
        }
    }
    
    func applyIOEffect(_ ioEffect: IOEffect) -> Effect<Action> {
        .run { send in
            for try await result in runIOEffect(ioEffect) {
                await send(.ioResult(result))
            }
        }
    }
    
    func apply(_ transition: Transition, to state: inout State) -> Effect<Action> {
        let (nextState, ioEffect) = transition
        if let nextState { state = nextState }
        return ioEffect.map(applyIOEffect(_:)) ?? .none
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            let transition = Self.reduce(state, action)
            return apply(transition, to: &state)
        }
    }
    
}
