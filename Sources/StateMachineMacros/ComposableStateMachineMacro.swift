import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

/// Generates `body` with `NestedStateMachine` reducers for state machine composition.
///
/// Reads:
/// - `@NestedState` markers on State properties to discover child state paths
/// - `@Forward` markers on Input/IOResult enum cases to discover action mappings
public struct ComposableStateMachineMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let analyzer = try StateMachineAnalyzer.analyze(declaration: declaration)
        return analyzer.makeGeneratedMembers()
    }
}

// MARK: - Analyzer

private struct StateMachineAnalyzer {
    let parentName: String
    let parentDecl: DeclGroupSyntax
    let nestedStates: [NestedStateInfo]
    let inputForwards: [ForwardInfo]
    let ioResultForwards: [ForwardInfo]
    let hasEffectComposition: Bool

    static func analyze(declaration: some DeclGroupSyntax) throws -> Self {
        let parentName: String
        let parentDecl: DeclGroupSyntax

        if let structDecl = declaration.as(StructDeclSyntax.self) {
            parentName = structDecl.name.text
            parentDecl = structDecl
        } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            parentName = actorDecl.name.text
            parentDecl = actorDecl
        } else {
            throw MacroError.message("@ComposableStateMachine can only be attached to a struct or actor")
        }

        // Check if @EffectComposition is also present
        let hasEffectComposition = declaration.hasAttribute(named: "EffectComposition")

        // Find State struct and collect @NestedState properties
        let stateStruct = declaration.memberBlock.members
            .compactMap { $0.decl.as(StructDeclSyntax.self) }
            .first { $0.name.text == "State" }

        var nestedStates: [NestedStateInfo] = []
        if let stateStruct {
            for member in stateStruct.memberBlock.members {
                guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                      varDecl.hasAttribute(named: "NestedState") else { continue }

                // Extract property name and type
                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }

                    let propertyName = identifier.identifier.text

                    // Try to get type from annotation first, then from initializer
                    let fullType: String?
                    if let typeAnnotation = binding.typeAnnotation {
                        fullType = typeAnnotation.type.trimmedDescription
                    } else if let initializer = binding.initializer {
                        // Extract type from initializer like `CounterFeature.State()`
                        fullType = extractTypeFromInitializer(initializer.value)
                    } else {
                        fullType = nil
                    }

                    // Extract feature name from type (e.g., "CounterFeature.State" -> "CounterFeature")
                    if let fullType, let featureName = extractFeatureName(from: fullType) {
                        nestedStates.append(NestedStateInfo(
                            propertyName: propertyName,
                            stateType: fullType,
                            featureName: featureName
                        ))
                    }
                }
            }
        }

        // Find Input enum and collect @Forward cases
        let inputEnum = declaration.memberBlock.members
            .compactMap { $0.decl.as(EnumDeclSyntax.self) }
            .first { $0.name.text == "Input" }

        var inputForwards: [ForwardInfo] = []
        if let inputEnum {
            inputForwards = try collectForwards(from: inputEnum, isIOResult: false)
        }

        // Find IOResult enum/typealias and collect @Forward cases
        var ioResultForwards: [ForwardInfo] = []
        let ioResultEnum = declaration.memberBlock.members
            .compactMap { $0.decl.as(EnumDeclSyntax.self) }
            .first { $0.name.text == "IOResult" }

        if let ioResultEnum {
            ioResultForwards = try collectForwards(from: ioResultEnum, isIOResult: true)
        }

        return .init(
            parentName: parentName,
            parentDecl: parentDecl,
            nestedStates: nestedStates,
            inputForwards: inputForwards,
            ioResultForwards: ioResultForwards,
            hasEffectComposition: hasEffectComposition
        )
    }

    private static func extractFeatureName(from stateType: String) -> String? {
        // "CounterFeature.State" -> "CounterFeature"
        // "SomeModule.CounterFeature.State" -> "SomeModule.CounterFeature"
        if stateType.hasSuffix(".State") {
            return String(stateType.dropLast(".State".count))
        }
        return nil
    }

    private static func extractTypeFromInitializer(_ expr: ExprSyntax) -> String? {
        // Handle `CounterFeature.State()` - a function call expression
        if let funcCall = expr.as(FunctionCallExprSyntax.self) {
            // The calledExpression is `CounterFeature.State`
            let calledExpr = funcCall.calledExpression.trimmedDescription
            return calledExpr
        }
        // Handle direct member access without call `CounterFeature.State`
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            return memberAccess.trimmedDescription
        }
        return nil
    }

    private static func collectForwards(from enumDecl: EnumDeclSyntax, isIOResult: Bool) throws -> [ForwardInfo] {
        var forwards: [ForwardInfo] = []

        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }

            for element in caseDecl.elements {
                guard let forwardAttr = findForwardAttribute(in: caseDecl) else { continue }

                let caseName = element.name.text
                let associatedValues = element.parameterClause?.parameters.map { param -> AssociatedValue in
                    let label = param.firstName?.text
                    let type = param.type.trimmedDescription
                    return AssociatedValue(label: label, type: type)
                } ?? []

                // Parse the @Forward argument to extract target info
                let targetInfo = try parseForwardTarget(from: forwardAttr)

                forwards.append(ForwardInfo(
                    parentCaseName: caseName,
                    associatedValues: associatedValues,
                    targetFeature: targetInfo.featureName,
                    targetEnumType: targetInfo.enumType,
                    targetCaseName: targetInfo.caseName,
                    isWholeEnumForward: targetInfo.isWholeEnumForward,
                    isIOResult: isIOResult
                ))
            }
        }

        return forwards
    }

    private static func findForwardAttribute(in caseDecl: EnumCaseDeclSyntax) -> AttributeSyntax? {
        for attr in caseDecl.attributes {
            if case let .attribute(attribute) = attr,
               isAttributeNamed(attribute, name: "Forward") {
                return attribute
            }
        }
        return nil
    }

    static func isAttributeNamed(_ attribute: AttributeSyntax, name: String) -> Bool {
        // Try IdentifierTypeSyntax first (most common case)
        if let identType = attribute.attributeName.as(IdentifierTypeSyntax.self) {
            return identType.name.text == name
        }
        // Fallback to trimmed description
        let attrName = attribute.attributeName.trimmedDescription
        return attrName == name || attrName.hasPrefix("\(name)<") || attrName.hasPrefix("\(name)(")
    }

    private static func parseForwardTarget(from attribute: AttributeSyntax) throws -> ForwardTarget {
        guard let arguments = attribute.arguments else {
            throw MacroError.message("@Forward requires a target argument")
        }

        // The argument could be:
        // 1. MemberAccessExpr: CounterFeature.Input.incrementTapped
        // 2. MemberAccessExpr with .self: PresetsFeature.IOResult.self

        let argString: String
        if let labeledList = arguments.as(LabeledExprListSyntax.self),
           let first = labeledList.first {
            argString = first.expression.trimmedDescription
        } else {
            argString = arguments.trimmedDescription
        }

        // Parse the member access expression
        // Examples:
        //   "CounterFeature.Input.incrementTapped" -> feature=CounterFeature, enum=Input, case=incrementTapped
        //   "PresetsFeature.IOResult.self" -> feature=PresetsFeature, enum=IOResult, case=self (whole enum)

        let components = argString.split(separator: ".").map(String.init)

        guard components.count >= 3 else {
            throw MacroError.message("@Forward target must be in format FeatureName.EnumType.caseName (got: \(argString))")
        }

        let caseName = components.last!
        let enumType = components[components.count - 2]
        let featureName = components.dropLast(2).joined(separator: ".")

        let isWholeEnumForward = caseName == "self"

        return ForwardTarget(
            featureName: featureName,
            enumType: enumType,
            caseName: isWholeEnumForward ? nil : caseName,
            isWholeEnumForward: isWholeEnumForward
        )
    }

    func makeGeneratedMembers() -> [DeclSyntax] {
        // If @EffectComposition is present, it generates `body`, so we should not generate it.
        // Instead, we need a different approach - perhaps a computed property that returns the nested reducers.
        // For now, let's generate `body` only if @EffectComposition is not present.

        if hasEffectComposition {
            // When both macros are present, @EffectComposition generates body with nestedBody.
            // We generate nestedBody here.
            return makeNestedBodyMembers()
        } else {
            // We generate the full body
            return makeFullBodyMembers()
        }
    }

    private func makeNestedBodyMembers() -> [DeclSyntax] {
        let access = accessPrefix
        let nestedReducers = makeNestedStateMachineReducers()

        if nestedReducers.isEmpty {
            // No nested reducers, generate empty nestedBody
            let nestedBody: DeclSyntax = """
            @ReducerBuilder<State, Action>
            \(raw: access)var nestedBody: some Reducer<State, Action> {
                EmptyReducer()
            }
            """
            return [nestedBody]
        }

        let reducerList = nestedReducers.joined(separator: "\n\n")

        let nestedBody: DeclSyntax = """
        @ReducerBuilder<State, Action>
        \(raw: access)var nestedBody: some Reducer<State, Action> {
            \(raw: reducerList)
        }
        """

        return [nestedBody]
    }

    private func makeFullBodyMembers() -> [DeclSyntax] {
        let access = accessPrefix
        let nestedReducers = makeNestedStateMachineReducers()

        let reducerList: String
        if nestedReducers.isEmpty {
            reducerList = ""
        } else {
            reducerList = nestedReducers.joined(separator: "\n\n") + "\n\n"
        }

        let body: DeclSyntax = """
        @ReducerBuilder<State, Action>
        \(raw: access)var body: some Reducer<State, Action> {
            \(raw: reducerList)Reduce { state, action in
                let transition = Self.reduce(state, action)
                return apply(transition, to: &state)
            }
        }
        """

        // Also generate helper methods if not using @EffectComposition
        let reduce: DeclSyntax = """
        \(raw: access)static func reduce(_ state: State, _ action: Action) -> Transition {
            return switch Action.map(action) {
            case nil: identity
            case .input(let input)?: reduceInput(state, input)
            case .ioResult(let ioResult)?: reduceIOResult(state, ioResult)
            }
        }
        """

        let apply: DeclSyntax = """
        \(raw: access)func apply(_ transition: Transition, to state: inout State) -> Effect<Action> {
            let (nextState, ioEffect) = transition
            if let nextState { state = nextState }
            guard let ioEffect else { return .none }
            return .run { send in
                for try await result in runIOEffect(ioEffect) {
                    await send(.ioResult(result))
                }
            }
        }
        """

        return [reduce, apply, body]
    }

    private func makeNestedStateMachineReducers() -> [String] {
        // Group forwards by feature
        var featureForwards: [String: (inputForwards: [ForwardInfo], ioResultForwards: [ForwardInfo])] = [:]

        for forward in inputForwards {
            var entry = featureForwards[forward.targetFeature] ?? ([], [])
            entry.inputForwards.append(forward)
            featureForwards[forward.targetFeature] = entry
        }

        for forward in ioResultForwards {
            var entry = featureForwards[forward.targetFeature] ?? ([], [])
            entry.ioResultForwards.append(forward)
            featureForwards[forward.targetFeature] = entry
        }

        // Generate NestedStateMachine for each nested state that has forwards
        var reducers: [String] = []

        for nestedState in nestedStates {
            guard let forwards = featureForwards[nestedState.featureName] else { continue }

            let inputMappings = forwards.inputForwards.map { forward -> String in
                let valueForwarding = makeValueForwarding(forward.associatedValues)
                return "case .\(forward.parentCaseName)\(valueForwarding.pattern): return .input(.\(forward.targetCaseName!)\(valueForwarding.call))"
            }

            let ioResultMappings = forwards.ioResultForwards.map { forward -> String in
                if forward.isWholeEnumForward {
                    // Whole enum forward: case .presetsResult(let childResult) -> return .ioResult(childResult)
                    return "case .\(forward.parentCaseName)(let childResult): return .ioResult(childResult)"
                } else {
                    let valueForwarding = makeValueForwarding(forward.associatedValues)
                    return "case .\(forward.parentCaseName)\(valueForwarding.pattern): return .ioResult(.\(forward.targetCaseName!)\(valueForwarding.call))"
                }
            }

            let hasInputMappings = !inputMappings.isEmpty
            let hasIOResultMappings = !ioResultMappings.isEmpty

            var toChildActionBody: String

            if hasInputMappings && hasIOResultMappings {
                let inputCases = inputMappings.joined(separator: "\n                ")
                let ioResultCases = ioResultMappings.joined(separator: "\n                ")

                toChildActionBody = """
                switch action {
                        case .input(let input):
                            switch input {
                            \(inputCases)
                            default: return nil
                            }
                        case .ioResult(let ioResult):
                            switch ioResult {
                            \(ioResultCases)
                            default: return nil
                            }
                        }
                """
            } else if hasInputMappings {
                let inputCases = inputMappings.joined(separator: "\n                ")
                toChildActionBody = """
                guard case .input(let input) = action else { return nil }
                        switch input {
                        \(inputCases)
                        default: return nil
                        }
                """
            } else if hasIOResultMappings {
                let ioResultCases = ioResultMappings.joined(separator: "\n                ")
                toChildActionBody = """
                guard case .ioResult(let ioResult) = action else { return nil }
                        switch ioResult {
                        \(ioResultCases)
                        default: return nil
                        }
                """
            } else {
                continue // No mappings, skip this nested state
            }

            // Generate fromChildAction to map child IOResult back to parent
            let fromChildActionBody: String
            if hasIOResultMappings {
                // Generate reverse mapping for IOResult
                let reverseMappings = forwards.ioResultForwards.map { forward -> String in
                    if forward.isWholeEnumForward {
                        // Whole enum forward: .ioResult(result) -> .ioResult(.presetsResult(result))
                        return "case .ioResult(let result): return .ioResult(.\(forward.parentCaseName)(result))"
                    } else {
                        // Individual case forward - not typically used for fromChildAction
                        return "case .ioResult(let result): return .ioResult(.\(forward.parentCaseName)(result))"
                    }
                }
                let reverseCases = reverseMappings.joined(separator: "\n                    ")
                fromChildActionBody = """
                switch childAction {
                            \(reverseCases)
                            default: return nil
                            }
                """
            } else {
                fromChildActionBody = "nil"
            }

            let reducer = """
            NestedStateMachine<State, Action, \(nestedState.featureName)>(
                    state: \\.\(nestedState.propertyName),
                    toChildAction: { (action: Action) -> \(nestedState.featureName).Action? in
                        \(toChildActionBody)
                    },
                    fromChildAction: { @Sendable (childAction: \(nestedState.featureName).Action) -> Action? in
                        \(fromChildActionBody)
                    },
                    child: { \(nestedState.featureName)() }
                )
            """

            reducers.append(reducer)
        }

        return reducers
    }

    private func makeValueForwarding(_ associatedValues: [AssociatedValue]) -> (pattern: String, call: String) {
        if associatedValues.isEmpty {
            return ("", "")
        }

        let bindings = associatedValues.enumerated().map { index, value -> String in
            let name = value.label ?? "v\(index)"
            return "let \(name)"
        }

        let args = associatedValues.enumerated().map { index, value -> String in
            let name = value.label ?? "v\(index)"
            // Include label in call if present: `label: value`
            if let label = value.label {
                return "\(label): \(name)"
            } else {
                return name
            }
        }

        return ("(\(bindings.joined(separator: ", ")))", "(\(args.joined(separator: ", ")))")
    }
}

// MARK: - Helper Types

private struct NestedStateInfo {
    let propertyName: String
    let stateType: String
    let featureName: String
}

private struct AssociatedValue {
    let label: String?
    let type: String
}

private struct ForwardInfo {
    let parentCaseName: String
    let associatedValues: [AssociatedValue]
    let targetFeature: String
    let targetEnumType: String
    let targetCaseName: String?
    let isWholeEnumForward: Bool
    let isIOResult: Bool
}

private struct ForwardTarget {
    let featureName: String
    let enumType: String
    let caseName: String?
    let isWholeEnumForward: Bool
}

// MARK: - Extensions

private extension StateMachineAnalyzer {
    var accessPrefix: String {
        parentAccessModifier.map { $0 + " " } ?? ""
    }

    var parentAccessModifier: String? {
        for modifier in parentDecl.modifiers {
            let text = modifier.name.text
            if text == "public" || text == "package" {
                return text
            }
        }
        return nil
    }
}

private extension DeclGroupSyntax {
    func hasAttribute(named name: String) -> Bool {
        for attr in attributes {
            if case let .attribute(attribute) = attr,
               StateMachineAnalyzer.isAttributeNamed(attribute, name: name) {
                return true
            }
        }
        return false
    }
}

private extension VariableDeclSyntax {
    func hasAttribute(named name: String) -> Bool {
        for attr in attributes {
            if case let .attribute(attribute) = attr,
               StateMachineAnalyzer.isAttributeNamed(attribute, name: name) {
                return true
            }
        }
        return false
    }
}

private extension SyntaxProtocol {
    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
