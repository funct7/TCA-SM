import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import StateMachineMacros

final class ComposableStateMachineMacroTests: XCTestCase {
    private let macros: [String: Macro.Type] = [
        "ComposableStateMachine": ComposableStateMachineMacro.self,
        "Forward": ForwardMacro.self,
        "ForwardValue": ForwardValueMacro.self,
        "NestedFeature": NestedFeatureMacro.self,
        "NestedState": NestedStateMacro.self,
    ]

    func testExistingInputAndIOResultForwardingExpansion() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var child = ChildFeature.State()
                }

                enum Input {
                    @Forward(ChildFeature.Input.setValue)
                    case setChildValue(value: Int)
                }

                enum IOResult {
                    @Forward(ChildFeature.IOResult.self)
                    case childResult(ChildFeature.IOResult)
                }
            }
            """,
            expandedSource:
            """
            struct ParentFeature: StateMachine {
                struct State {
                    var child = ChildFeature.State()
                }

                enum Input {
                    case setChildValue(value: Int)
                }

                enum IOResult {
                    case childResult(ChildFeature.IOResult)
                }

                static func reduce(_ state: State, _ action: Action) -> Transition {
                    return switch Action.map(action) {
                    case nil:
                        identity
                    case .input(let input)?:
                        reduceInput(state, input)
                    case .ioResult(let ioResult)?:
                        reduceIOResult(state, ioResult)
                    }
                }

                func apply(_ transition: Transition, to state: inout State) -> Effect<Action> {
                    let (nextState, ioEffect) = transition
                    if let nextState {
                        state = nextState
                    }
                    guard let ioEffect else {
                        return .none
                    }
                    return .run { send in
                        for try await result in runIOEffect(ioEffect) {
                            await send(.ioResult(result))
                        }
                    }
                }

                @ReducerBuilder<State, Action>
                var body: some Reducer<State, Action> {
                    NestedStateMachine<State, Action, ChildFeature>(
                        state: \\.child,
                        toChildAction: { (action: Action) -> ChildFeature.Action? in
                            switch action {
                        case .input(let input):
                            switch input {
                            case .setChildValue(let value):
                                return .input(.setValue(value: value))
                            default:
                                return nil
                            }
                        case .ioResult(let ioResult):
                            switch ioResult {
                            case .childResult(let childResult):
                                return .ioResult(childResult)
                            default:
                                return nil
                            }
                        }
                        },
                        fromChildAction: { @Sendable (childAction: ChildFeature.Action) -> Action? in
                            switch childAction {
                            case .ioResult(let result):
                                return .ioResult(.childResult(result))
                            default:
                                return nil
                            }
                        },
                        child: {
                            ChildFeature()
                        }
                    )

                    Reduce { state, action in
                            let transition = Self.reduce(state, action)
                            return apply(transition, to: &state)
                        }
                }
            }
            """,
            macros: macros
        )
    }

    func testValueForwardingExpansion() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var load = NumberFactLoader.State()
                }

                enum Input {
                    @ForwardValue(NumberFactLoader.Input.self)
                    case load(Int)
                }
            }
            """,
            expandedSource:
            """
            struct ParentFeature: StateMachine {
                struct State {
                    var load = NumberFactLoader.State()
                }

                enum Input {
                    case load(Int)
                }

                static func reduce(_ state: State, _ action: Action) -> Transition {
                    return switch Action.map(action) {
                    case nil:
                        identity
                    case .input(let input)?:
                        reduceInput(state, input)
                    case .ioResult(let ioResult)?:
                        reduceIOResult(state, ioResult)
                    }
                }

                func apply(_ transition: Transition, to state: inout State) -> Effect<Action> {
                    let (nextState, ioEffect) = transition
                    if let nextState {
                        state = nextState
                    }
                    guard let ioEffect else {
                        return .none
                    }
                    return .run { send in
                        for try await result in runIOEffect(ioEffect) {
                            await send(.ioResult(result))
                        }
                    }
                }

                @ReducerBuilder<State, Action>
                var body: some Reducer<State, Action> {
                    NestedStateMachine<State, Action, NumberFactLoader>(
                        state: \\.load,
                        toChildAction: { (action: Action) -> NumberFactLoader.Action? in
                            guard case .input(let input) = action else {
                                return nil
                            }
                        switch input {
                        case .load(let value):
                                return .input(value)
                        default:
                                return nil
                        }
                        },
                        fromChildAction: { @Sendable (childAction: NumberFactLoader.Action) -> Action? in
                            nil
                        },
                        child: {
                            NumberFactLoader()
                        }
                    )

                    Reduce { state, action in
                            let transition = Self.reduce(state, action)
                            return apply(transition, to: &state)
                        }
                }
            }
            """,
            macros: macros
        )
    }

    func testForwardValueRequiresOneAssociatedValue() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var load = NumberFactLoader.State()
                }

                enum Input {
                    @ForwardValue(NumberFactLoader.Input.self)
                    case load(Int, String)
                }
            }
            """,
            expandedSource:
            """
            struct ParentFeature: StateMachine {
                struct State {
                    var load = NumberFactLoader.State()
                }

                enum Input {
                    case load(Int, String)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ForwardValue requires exactly one associated value on Input.load",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    func testForwardValueRequiresChildInputSelfTarget() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var load = NumberFactLoader.State()
                }

                enum Input {
                    @ForwardValue(NumberFactLoader.IOResult.self)
                    case load(Int)
                }
            }
            """,
            expandedSource:
            """
            struct ParentFeature: StateMachine {
                struct State {
                    var load = NumberFactLoader.State()
                }

                enum Input {
                    case load(Int)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ForwardValue target must be in format FeatureName.Input.self (got: NumberFactLoader.IOResult.self)",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    func testForwardValueCannotBeUsedOnIOResult() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var load = NumberFactLoader.State()
                }

                enum IOResult {
                    @ForwardValue(NumberFactLoader.IOResult.self)
                    case loadResult(NumberFactLoader.IOResult)
                }
            }
            """,
            expandedSource:
            """
            struct ParentFeature: StateMachine {
                struct State {
                    var load = NumberFactLoader.State()
                }

                enum IOResult {
                    case loadResult(NumberFactLoader.IOResult)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ForwardValue can only be used on Input cases",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }
}
