import Foundation
import ComposableArchitecture

public protocol MappableAction {
    associatedtype Input
    associatedtype IOResult
    
    static func input(_ value: Input) -> Self
    static func ioResult(_ value: IOResult) -> Self
    static func map(_ action: Self) -> XOR<Input, IOResult>?
}

public extension StateMachine
where Self : Reducer,
      Action : MappableAction,
      Action.Input == Input,
      Action.IOResult == IOResult
{
    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        guard let mapped = Action.map(action) else { return .none }
        
        let transition = switch mapped {
        case .first(let input): Self.reduceInput(state, input)
        case .second(let ioResult): Self.reduceIOResult(state, ioResult)
        }
        
        return apply(transition, to: &state)
    }
    
    @inlinable
    func apply(_ transition: Transition, to state: inout State) -> Effect<Action> {
        if let next = transition.0 { state = next }
        guard let effect = transition.1 else { return .none }
        
        return .run { send in
            guard let result = await runIOEffect(effect) else { return }
            await send(.ioResult(result))
        }
    }
}
