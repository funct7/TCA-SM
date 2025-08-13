import ComposableArchitecture

public protocol MappableAction {
    associatedtype Input
    associatedtype IOResult

    static func input(_ value: Input) -> Self
    static func ioResult(_ value: IOResult) -> Self
    static func map(_ action: Self) -> XOR<Input, IOResult>?
}

public extension StateMachine where Self: Reducer, Action: MappableAction, Action.Input == Input, Action.IOResult == IOResult {
    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        guard let mapped = Action.map(action) else { return .none }
        let transition: Transition
        switch mapped {
        case .first(let input):
            transition = Self.reduceInput(state, input)
        case .second(let ioResult):
            transition = Self.reduceIOResult(state, ioResult)
        }
        return apply(transition, to: &state)
    }

    @inlinable
    public func apply(_ transition: Transition, to state: inout State) -> Effect<Action> {
        if let next = transition.0 { state = next }
        guard let effect = transition.1 else { return .none }
        return .run { send in
            if let result = await self.runIOEffect(effect) {
                await send(Action.ioResult(result))
            }
        }
    }
}