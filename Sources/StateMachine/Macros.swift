// imports removed

// MARK: - StateMachine

/// Generates the Action typealias for StateMachine types.
///
/// This macro generates:
/// ```swift
/// typealias Action = StateMachineEvent<Input, IOResult>
/// ```
///
/// Example:
/// ```swift
/// @StateMachine
/// struct MyFeature: StateMachine {
///     struct State { ... }
///     enum Input { ... }
///     enum IOResult { ... }
///     // No need for: typealias Action = StateMachineEvent<Input, IOResult>
/// }
/// ```
@attached(member, names: named(Action))
public macro StateMachine() = #externalMacro(
    module: "StateMachineMacros",
    type: "StateMachineMacro"
)

// MARK: - ComposableEffect (internal use)
// Note: @ComposableEffect is auto-applied by @ComposableEffectRunner.
// It remains available for internal use but is not typically needed standalone.

@attached(member, names: arbitrary)
@attached(extension, conformances: ComposableEffectConvertible)
public macro ComposableEffect() = #externalMacro(
    module: "StateMachineMacros",
    type: "ComposableEffectMembersMacro"
)

// MARK: - ComposableEffectRunner

/// Generates effect running infrastructure for composable effects.
///
/// This macro auto-detects `@ComposableStateMachine` and includes `nestedBody` automatically.
@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro ComposableEffectRunner() = #externalMacro(
    module: "StateMachineMacros",
    type: "EffectRunnerMacro"
)

// MARK: - ComposableStateMachine

/// Enables state machine composition by generating `body` with `NestedStateMachine` reducers.
///
/// Use this macro on features that compose child state machines. It reads:
/// - `@NestedState` markers on State properties to discover child state paths
/// - `@Forward` markers on Input/IOResult enum cases to discover action mappings
///
/// Example:
/// ```swift
/// @ComposableStateMachine
/// struct ParentFeature: StateMachine {
///     struct State {
///         @NestedState var counter: CounterFeature.State
///     }
///     enum Input {
///         @Forward(CounterFeature.Input.incrementTapped)
///         case counterIncrement
///     }
///     // ...
/// }
/// ```
@attached(member, names: arbitrary)
public macro ComposableStateMachine() = #externalMacro(
    module: "StateMachineMacros",
    type: "ComposableStateMachineMacro"
)

// MARK: - NestedState

/// Marks a State property as containing a nested feature's state.
///
/// The `@ComposableStateMachine` macro reads this to discover child state paths.
///
/// Example:
/// ```swift
/// struct State {
///     @NestedState var counter: CounterFeature.State
///     @NestedState var presets: PresetsFeature.State
/// }
/// ```
@attached(peer)
public macro NestedState() = #externalMacro(
    module: "StateMachineMacros",
    type: "NestedStateMacro"
)

// MARK: - Forward

/// Marks an Input or IOResult case as forwarding to a child feature's action.
///
/// The `@ComposableStateMachine` macro reads this to generate action mappings.
///
/// Example:
/// ```swift
/// enum Input {
///     @Forward(CounterFeature.Input.incrementTapped)
///     case counterIncrement
///
///     @Forward(CounterFeature.Input.setValue)
///     case counterSetValue(Int)  // associated values are forwarded
/// }
///
/// enum IOResult {
///     @Forward(PresetsFeature.IOResult.self)
///     case presetsResult(PresetsFeature.IOResult)
/// }
/// ```
@attached(peer)
public macro Forward<T>(_ target: T) = #externalMacro(
    module: "StateMachineMacros",
    type: "ForwardMacro"
)

// MARK: - NestedFeature

/// Declares a nested feature for edge cases like computed properties.
///
/// Use this when `@NestedState` on a stored property isn't sufficient.
///
/// Example:
/// ```swift
/// @ComposableStateMachine
/// @NestedFeature(CounterFeature.self, state: \.derivedCounter)
/// struct Feature: StateMachine { ... }
/// ```
@attached(peer)
public macro NestedFeature<T>(_ feature: T.Type, state: KeyPath<Any, Any>) = #externalMacro(
    module: "StateMachineMacros",
    type: "NestedFeatureMacro"
)
