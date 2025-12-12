@attached(member, names: arbitrary)
@attached(extension, conformances: ComposableEffectConvertible)
public macro ComposableEffect() = #externalMacro(
    module: "StateMachineMacros",
    type: "ComposableEffectMembersMacro"
)
