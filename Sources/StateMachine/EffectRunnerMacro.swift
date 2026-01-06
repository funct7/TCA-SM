@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro ComposableEffectRunner(isBodyComposable: Bool = false) = #externalMacro(
    module: "StateMachineMacros",
    type: "EffectRunnerMacro"
)
