@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro ComposableEffectRunner() = #externalMacro(
    module: "StateMachineMacros",
    type: "EffectRunnerMacro"
)
