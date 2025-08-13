import ComposableArchitecture

// MARK: - StateMachine

public protocol StateMachine {
    associatedtype State
    associatedtype Action
    associatedtype Input: Sendable
    associatedtype IOEffect: Sendable
    associatedtype IOResult: Sendable

    typealias Transition = (State?, IOEffect?)

    static func reduceInput(_ state: State, _ input: Input) -> Transition
    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition
    func runIOEffect(_ ioEffect: IOEffect) async -> IOResult?
}

// MARK: - Transition helpers only

public extension StateMachine {
    static var undefined: Transition { (nil, nil) }
    static var identity: Transition { (nil, nil) }
    static func nextState(_ state: State) -> Transition { (state, nil) }
    static func run(_ effect: IOEffect) -> Transition { (nil, effect) }
    static func transition(_ state: State, effect: IOEffect) -> Transition { (state, effect) }
    static func unsafe(_ action: @escaping () -> Void) -> Transition { action(); return (nil, nil) }
}

// MARK: - Specialized reducer implementation for MappableAction-based Actions

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