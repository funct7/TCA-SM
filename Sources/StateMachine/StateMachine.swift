import ComposableArchitecture

// MARK: - StateMachine

public protocol StateMachine: Reducer where Action: MappableAction, Action.Input == Input, Action.IOResult == IOResult {
    associatedtype Input: Sendable
    associatedtype IOEffect: Sendable
    associatedtype IOResult: Sendable

    typealias Transition = (State?, IOEffect?)

    static func reduceInput(_ state: State, _ input: Input) -> Transition
    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition
    func runIOEffect(_ ioEffect: IOEffect) async -> IOResult?
}

// MARK: - Default implementation & helpers

public extension StateMachine {
    // Transition helpers
    static var undefined: Transition { (nil, nil) }
    static var identity: Transition { (nil, nil) }
    static func nextState(_ state: State) -> Transition { (state, nil) }
    static func run(_ effect: IOEffect) -> Transition { (nil, effect) }
    static func transition(_ state: State, effect: IOEffect) -> Transition { (state, effect) }
    static func unsafe(_ action: @escaping () -> Void) -> Transition { action(); return (nil, nil) }

    // Event reducer
    static func reduce(_ state: State, _ event: StateMachineEvent<Input, IOResult>) -> Transition {
        switch event {
        case .input(let input):
            return Self.reduceInput(state, input)
        case .ioResult(let result):
            return Self.reduceIOResult(state, result)
        }
    }

    // Reducer conformance
    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        guard let event = Action.map(action) else { return .none }
        let transition = Self.reduce(state, event)
        return apply(transition, to: &state)
    }

    // Applies a transition to the state and returns an Effect that executes IOEffect if present
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