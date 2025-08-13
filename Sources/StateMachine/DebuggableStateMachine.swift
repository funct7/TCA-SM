import Foundation
import ComposableArchitecture

public protocol DebuggableStateMachine : StateMachine {
    typealias CancelID = any Hashable & Sendable
    static func makeIOEffectCancelID(_ state: State, _ action: Action) -> CancelID?
}

public extension DebuggableStateMachine where
Action : MappableAction,
Action : Sendable,
Action.Input == Input,
Action.IOResult == IOResult
{
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            let transition = Self.reduce(state, action)
            let effect = apply(transition, to: &state)
            let cancelID = Self.makeIOEffectCancelID(state, action)
            return cancelID.map { effect.cancellable(id: $0, cancelInFlight: true) } ?? effect
        }
    }
    
}
