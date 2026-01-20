import ComposableArchitecture
import Combine

/// A reducer that maps parent actions to child actions without using Scope + CasePaths.
///
/// This enables state machine composition where parent `Input`/`IOResult` cases
/// are forwarded to nested child state machines.
///
/// Usage:
/// ```swift
/// var body: some Reducer<State, Action> {
///     NestedStateMachine(
///         state: \.counter,
///         toChildAction: { action in
///             guard case .input(let input) = action else { return nil }
///             switch input {
///             case .counterIncrement: return .input(.incrementTapped)
///             default: return nil
///             }
///         },
///         fromChildAction: { childAction in
///             // Map child IOResult back to parent
///             guard case .ioResult(let result) = childAction else { return nil }
///             return .ioResult(.counterResult(result))
///         },
///         child: { CounterFeature() }
///     )
///     // ... parent's own reducer
/// }
/// ```
public struct NestedStateMachine<ParentState, ParentAction, Child: Reducer>: Reducer {
    public typealias State = ParentState
    public typealias Action = ParentAction

    private let statePath: WritableKeyPath<ParentState, Child.State>
    private let toChildAction: (ParentAction) -> Child.Action?
    private let fromChildAction: @Sendable (Child.Action) -> ParentAction?
    private let child: () -> Child

    /// Creates a nested state machine reducer.
    ///
    /// - Parameters:
    ///   - state: WritableKeyPath to the child's state within the parent's state.
    ///   - toChildAction: A function that maps parent actions to child actions.
    ///                    Returns `nil` for actions that shouldn't be forwarded.
    ///   - fromChildAction: A function that maps child actions back to parent actions.
    ///                      Used to propagate child effects to the parent.
    ///   - child: A closure that creates the child reducer.
    public init(
        state: WritableKeyPath<ParentState, Child.State>,
        toChildAction: @escaping (ParentAction) -> Child.Action?,
        fromChildAction: @escaping @Sendable (Child.Action) -> ParentAction?,
        child: @escaping () -> Child
    ) {
        self.statePath = state
        self.toChildAction = toChildAction
        self.fromChildAction = fromChildAction
        self.child = child
    }

    public func reduce(into state: inout ParentState, action: ParentAction) -> Effect<ParentAction> {
        guard let childAction = toChildAction(action) else {
            return .none
        }
        // Run child reducer on scoped state and capture the effect
        let childEffect = child().reduce(into: &state[keyPath: statePath], action: childAction)

        // Map child effect's actions to parent actions
        // We wrap the child effect and transform its actions
        return childEffect
            .map { childAction -> ParentAction in
                // If fromChildAction returns nil, we need a fallback.
                // This shouldn't happen in practice since child effects should only
                // produce actions we can map (IOResults).
                // Use a placeholder action - but we need to handle this properly.
                fromChildAction(childAction)!
            }
    }
}
