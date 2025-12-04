@attached(member, names: arbitrary)
public macro ComposableEffectMembers() = #externalMacro(
    module: "StateMachineMacros",
    type: "ComposableEffectMembersMacro"
)
