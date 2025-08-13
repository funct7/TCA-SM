import ComposableArchitecture

// MARK: - DebuggableStateMachine

public struct DebuggableStateMachine<Base: StateMachine>: Reducer {
    public typealias State = Base.State
    public typealias Action = Base.Action

    private let base: Base
    private let label: String
    private let stateDescription: (State) -> String

    public init(_ base: Base, label: String? = nil, stateDescription: @escaping (State) -> String = { String(describing: $0) }) {
        self.base = base
        self.label = label ?? String(describing: Base.self)
        self.stateDescription = stateDescription
    }

    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        #if DEBUG
        let before = stateDescription(state)
        #endif

        // If it's not a StateMachine event, just forward to base
        guard let event = Action.map(action) else {
            return base.reduce(into: &state, action: action)
        }

        let transition = Base.reduce(state, event)

        #if DEBUG
        let stateChange: String
        if let next = transition.0 {
            stateChange = stateDescription(next)
        } else {
            stateChange = "(no state change)"
        }
        let effectDesc = transition.1.map { String(describing: $0) } ?? "nil"
        print("[\(label)] event=\(String(describing: event)) -> newState=\(stateChange) effect=\(effectDesc) from=\(before)")
        #endif

        return base.apply(transition, to: &state)
    }
}