@attached(member, names: arbitrary)
@attached(extension, conformances: ComposableEffectConvertible)
public macro ComposableEffectMembers() = #externalMacro(
    module: "StateMachineMacros",
    type: "ComposableEffectMembersMacro"
)
