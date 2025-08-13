import Foundation
import ComposableArchitecture

// MARK: - DebuggableStateMachine

public struct DebuggableStateMachine<Base: StateMachine> : Reducer where Base: Reducer, Base.Action: MappableAction, Base.Action.Input == Base.Input, Base.Action.IOResult == Base.IOResult {
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
        
        guard let mapped = Action.map(action) else { return base.reduce(into: &state, action: action) }
        
        let transition: Base.Transition
        switch mapped {
        case .first(let input):
            transition = Base.reduceInput(state, input)
        case .second(let ioResult):
            transition = Base.reduceIOResult(state, ioResult)
        }
        
#if DEBUG
        let stateChange: String
        if let next = transition.0 {
            stateChange = stateDescription(next)
        } else {
            stateChange = "(no state change)"
        }
        let effectDesc = transition.1.map { String(describing: $0) } ?? "nil"
        print("[\(label)] mapped=\(String(describing: mapped)) -> newState=\(stateChange) effect=\(effectDesc) from=\(before)")
#endif
        
        return base.apply(transition, to: &state)
    }
}
