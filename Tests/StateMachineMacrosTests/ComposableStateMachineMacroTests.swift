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

    func testWholeEnumInputForwardingExpansion() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var child = ChildFeature.State()
                }

                enum Input {
                    @Forward(ChildFeature.Input.self)
                    case child(ChildFeature.Input)
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
                    case child(ChildFeature.Input)
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
                            guard case .input(let input) = action else {
                                return nil
                            }
                        switch input {
                        case .child(let childInput):
                                return .input(childInput)
                        default:
                                return nil
                        }
                        },
                        fromChildAction: { @Sendable (childAction: ChildFeature.Action) -> Action? in
                            nil
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

    func testIndividualIOResultForwardingExpansion() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var child = ChildFeature.State()
                }

                enum IOResult {
                    @Forward(ChildFeature.IOResult.loaded)
                    case childLoaded(Int)
                }
            }
            """,
            expandedSource:
            """
            struct ParentFeature: StateMachine {
                struct State {
                    var child = ChildFeature.State()
                }

                enum IOResult {
                    case childLoaded(Int)
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
                            guard case .ioResult(let ioResult) = action else {
                                return nil
                            }
                        switch ioResult {
                        case .childLoaded(let v0):
                                return .ioResult(.loaded(v0))
                        default:
                                return nil
                        }
                        },
                        fromChildAction: { @Sendable (childAction: ChildFeature.Action) -> Action? in
                            switch childAction {
                            case .ioResult(.loaded(let v0)):
                                return .ioResult(.childLoaded(v0))
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

    func testIndividualIOResultReverseMappingsPrecedeWholeEnumCatchAll() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var child = ChildFeature.State()
                }

                enum IOResult {
                    @Forward(ChildFeature.IOResult.self)
                    case child(ChildFeature.IOResult)

                    @Forward(ChildFeature.IOResult.loaded)
                    case childLoaded(Int)
                }
            }
            """,
            expandedSource:
            """
            struct ParentFeature: StateMachine {
                struct State {
                    var child = ChildFeature.State()
                }

                enum IOResult {
                    case child(ChildFeature.IOResult)
                    case childLoaded(Int)
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
                            guard case .ioResult(let ioResult) = action else {
                                return nil
                            }
                        switch ioResult {
                        case .child(let childResult):
                                return .ioResult(childResult)
                                case .childLoaded(let v0):
                                return .ioResult(.loaded(v0))
                        default:
                                return nil
                        }
                        },
                        fromChildAction: { @Sendable (childAction: ChildFeature.Action) -> Action? in
                            switch childAction {
                            case .ioResult(.loaded(let v0)):
                                return .ioResult(.childLoaded(v0))
                                    case .ioResult(let result):
                                return .ioResult(.child(result))
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

    func testValueForwardingTreatsUnderscoreLabelAsUnlabeled() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var load = NumberFactLoader.State()
                }

                enum Input {
                    @ForwardValue(NumberFactLoader.Input.self)
                    case load(_ value: Int)
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
                    case load(_ value: Int)
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

    func testWholeEnumForwardRequiresAssociatedValue() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var child = ChildFeature.State()
                }

                enum Input {
                    @Forward(ChildFeature.Input.self)
                    case child
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
                    case child
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Whole-enum @Forward on Input.child requires exactly one associated value of type ChildFeature.Input",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    func testWholeEnumForwardRequiresSingleAssociatedValue() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var child = ChildFeature.State()
                }

                enum IOResult {
                    @Forward(ChildFeature.IOResult.self)
                    case child(ChildFeature.IOResult, ChildFeature.IOResult)
                }
            }
            """,
            expandedSource:
            """
            struct ParentFeature: StateMachine {
                struct State {
                    var child = ChildFeature.State()
                }

                enum IOResult {
                    case child(ChildFeature.IOResult, ChildFeature.IOResult)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Whole-enum @Forward on IOResult.child requires exactly one associated value of type ChildFeature.IOResult",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    func testWholeEnumForwardRequiresMatchingAssociatedValueType() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var child = ChildFeature.State()
                }

                enum Input {
                    @Forward(ChildFeature.Input.self)
                    case child(String)
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
                    case child(String)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Whole-enum @Forward on Input.child requires exactly one associated value of type ChildFeature.Input",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    func testForwardValueIOResultExpansion() {
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
                            guard case .ioResult(let ioResult) = action else {
                                return nil
                            }
                        switch ioResult {
                        case .loadResult(let value):
                                return .ioResult(value)
                        default:
                                return nil
                        }
                        },
                        fromChildAction: { @Sendable (childAction: NumberFactLoader.Action) -> Action? in
                            switch childAction {
                            case .ioResult(let result):
                                return .ioResult(.loadResult(result))
                            default:
                                return nil
                            }
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

    func testDuplicateWholeEnumInputForwardEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var child = ChildFeature.State()
                }

                enum Input {
                    @Forward(ChildFeature.Input.self)
                    case childA(ChildFeature.Input)

                    @Forward(ChildFeature.Input.self)
                    case childB(ChildFeature.Input)
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
                    case childA(ChildFeature.Input)
                    case childB(ChildFeature.Input)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Whole-target forwarding for ChildFeature.Input is already declared on Input.childA",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    func testDuplicateWholeValueIOResultForwardEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @ComposableStateMachine
            struct ParentFeature: StateMachine {
                struct State {
                    @NestedState var load = NumberFactLoader.State()
                }

                enum IOResult {
                    @ForwardValue(NumberFactLoader.IOResult.self)
                    case loadA(NumberFactLoader.IOResult)

                    @ForwardValue(NumberFactLoader.IOResult.self)
                    case loadB(NumberFactLoader.IOResult)
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
                    case loadA(NumberFactLoader.IOResult)
                    case loadB(NumberFactLoader.IOResult)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Whole-target forwarding for NumberFactLoader.IOResult is already declared on IOResult.loadA",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }
}
