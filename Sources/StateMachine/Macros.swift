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

@attached(peer)
public macro ForwardInput<Root, Value>(_ child: KeyPath<Root, Value>) = #externalMacro(module: "StateMachineMacros", type: "ForwardInputMacro")

// MARK: - ForwardIOResult

@attached(peer)
public macro ForwardIOResult<Root, Value>(_ child: KeyPath<Root, Value>) = #externalMacro(module: "StateMachineMacros", type: "ForwardIOResultMacro")

// MARK: - NestedBody

@attached(peer, names: prefixed(_))
public macro NestedBody() = #externalMacro(module: "StateMachineMacros", type: "NestedBodyMacro")
