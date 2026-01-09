// imports removed

// MARK: - ComposableEffect

@attached(member, names: arbitrary)
@attached(extension, conformances: ComposableEffectConvertible)
public macro ComposableEffect() = #externalMacro(
    module: "StateMachineMacros",
    type: "ComposableEffectMembersMacro"
)

// MARK: - ComposableEffectRunner

@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro ComposableEffectRunner(isBodyComposable: Bool = false) = #externalMacro(
    module: "StateMachineMacros",
    type: "EffectRunnerMacro"
)

// MARK: - ForwardInput

/// Legacy: Marks a function as an input forwarder (requires `@ComposableEffectRunner`)
@attached(peer)
public macro ForwardInput<Root, Value>(_ child: KeyPath<Root, Value>) = #externalMacro(module: "StateMachineMacros", type: "ForwardInputMacro")

/// CaseKeyPath extraction mode: forwards input case directly to child action.
/// Works standalone (generates `{child}InputForwarder` reducer) or with `@ComposableEffectRunner`.
@attached(peer, names: arbitrary)
public macro ForwardInput<InputRoot, InputValue, ActionRoot, ActionValue>(
    _ inputCase: KeyPath<InputRoot, InputValue>,
    to childAction: KeyPath<ActionRoot, ActionValue>
) = #externalMacro(module: "StateMachineMacros", type: "ForwardInputMacro")

// MARK: - ForwardIOResult

/// Legacy: Marks a function as an IOResult forwarder (requires `@ComposableEffectRunner`)
@attached(peer)
public macro ForwardIOResult<Root, Value>(_ child: KeyPath<Root, Value>) = #externalMacro(module: "StateMachineMacros", type: "ForwardIOResultMacro")

/// CaseKeyPath extraction mode: forwards IOResult case directly to child action.
/// Works standalone (generates `{child}IOResultForwarder` reducer) or with `@ComposableEffectRunner`.
@attached(peer, names: arbitrary)
public macro ForwardIOResult<IOResultRoot, IOResultValue, ActionRoot, ActionValue>(
    _ ioResultCase: KeyPath<IOResultRoot, IOResultValue>,
    to childAction: KeyPath<ActionRoot, ActionValue>
) = #externalMacro(module: "StateMachineMacros", type: "ForwardIOResultMacro")

// MARK: - NestedBody

@attached(peer, names: prefixed(_))
public macro NestedBody() = #externalMacro(module: "StateMachineMacros", type: "NestedBodyMacro")
