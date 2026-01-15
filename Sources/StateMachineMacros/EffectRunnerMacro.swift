import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

public struct EffectRunnerMacro: MemberMacro, MemberAttributeMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let options = try EffectRunnerOptions.parse(from: attribute)
        let info = try EffectRunnerAnalyzer.analyze(declaration: declaration, options: options)
        return [info.makeEffectHandlerProtocol()] + info.makeComposableHelpers() + [info.makeRunIOEffect()]
    }
    
    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let enumDecl = member.as(EnumDeclSyntax.self), enumDecl.name.text == "IOEffect" else {
            return []
        }
        if (enumDecl as DeclSyntaxProtocol).hasAttribute(named: "ComposableEffect") {
            return []
        }
        return ["@ComposableEffect"]
    }
}

private struct EffectRunnerOptions {
    // Options are now auto-detected from other macros

    static func parse(from attribute: AttributeSyntax) throws -> Self {
        // No longer has parameters - options are auto-detected
        return .init()
    }
}

private struct ForwardMapper {
    enum MapperType {
        case input
        case ioResult
    }
    let type: MapperType
    let functionName: String
    let childKeyPath: String
    let childActionCase: String

    func makeEffectSend(parentActionVariable: String) -> String {
        let actionVar = "\(childKeyPath)Action"
        // e.g. (.input(child1Action)) or (.ioResult(child1Action))
        let childPayload = type == .input ? "(.input(\(actionVar)))" : "(.ioResult(\(actionVar)))"
        
        // We properly interpolate the values into the string.
        // Note: indentation here is for the generated code's readability, but primarily must be valid Swift.
        return """
        if let \(actionVar) = Self.\(functionName)(\(parentActionVariable)) {
            effects.append(.send(.\(childActionCase)\(childPayload)))
        }
        """
    }
}

private struct EffectRunnerAnalyzer {
    let parentName: String
    let ioEffectCases: [IOEffectCase]
    let parentDecl: DeclGroupSyntax
    let options: EffectRunnerOptions
    let forwardInputMappers: [ForwardMapper]
    let forwardIOResultMappers: [ForwardMapper]
    let hasComposableStateMachine: Bool

    static func analyze(declaration: some DeclGroupSyntax, options: EffectRunnerOptions) throws -> Self {
        let parentName: String
        let parentDecl: DeclGroupSyntax
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            parentName = structDecl.name.text
            parentDecl = structDecl
        } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            parentName = actorDecl.name.text
            parentDecl = actorDecl
        } else {
            throw MacroError.message("@ComposableEffectRunner can only be attached to a struct or actor")
        }

        // Auto-detect @ComposableStateMachine
        let hasComposableStateMachine = declaration.hasAttribute(named: "ComposableStateMachine")

        guard let ioEffectEnum = declaration.memberBlock.members
            .compactMap({ $0.decl.as(EnumDeclSyntax.self) })
            .first(where: { $0.name.text == "IOEffect" }) else {
            throw MacroError.message("@ComposableEffectRunner requires a nested enum named IOEffect")
        }
        if ioEffectEnum.containsCase(named: "merge") || ioEffectEnum.containsCase(named: "concat") {
            throw MacroError.message("@ComposableEffectRunner should not be used when IOEffect already declares merge/concat")
        }
        let cases = try ioEffectEnum.collectLeafCases()

        var inputMappers: [ForwardMapper] = []
        var ioResultMappers: [ForwardMapper] = []

        for member in parentDecl.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                if let attr = (funcDecl as DeclSyntaxProtocol).attribute(named: "ForwardInput") {
                    let keyPath = try parseKeyPathArgument(from: attr)
                    inputMappers.append(.init(type: .input, functionName: funcDecl.name.text, childKeyPath: keyPath, childActionCase: keyPath))
                }
                if let attr = (funcDecl as DeclSyntaxProtocol).attribute(named: "ForwardIOResult") {
                    let keyPath = try parseKeyPathArgument(from: attr)
                    ioResultMappers.append(.init(type: .ioResult, functionName: funcDecl.name.text, childKeyPath: keyPath, childActionCase: keyPath))
                }
            }
        }

        return .init(
            parentName: parentName,
            ioEffectCases: cases,
            parentDecl: parentDecl,
            options: options,
            forwardInputMappers: inputMappers,
            forwardIOResultMappers: ioResultMappers,
            hasComposableStateMachine: hasComposableStateMachine
        )
    }

    func makeRunIOEffect() -> DeclSyntax {
        let leafSwitchCases = ioEffectCases
            .map { $0.makeSwitchCase() }
            .joined(separator: "\n    ")
        let access = accessPrefix
        return """
        \(raw: access)func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream {
            switch ioEffect {
            case .merge:
                IOResultStream { continuation in
                    assertionFailure("IOEffect.merge is synthesized for composition and should not reach runIOEffect")
                    continuation.finish()
                }
            case .concat:
                IOResultStream { continuation in
                    assertionFailure("IOEffect.concat is synthesized for composition and should not reach runIOEffect")
                    continuation.finish()
                }
            \(raw: leafSwitchCases)
            }
        }
        """
    }

    func makeEffectHandlerProtocol() -> DeclSyntax {
        let protocolName = "EffectRunner"
        let requirementList = ioEffectCases
            .map { $0.makeHandlerRequirement(parentName: parentName) }
            .joined(separator: "\n    ")
        return """
        private protocol \(raw: protocolName) {
            \(raw: requirementList)
        }
        """
    }

    func makeComposableHelpers() -> [DeclSyntax] {
        let access = accessPrefix
        let reduce: DeclSyntax = """
        \(raw: access)static func reduce(_ state: State, _ action: Action) -> Transition {
            return switch Action.map(action) {
            case nil: identity
            case .input(let input)?: reduceInput(state, input)
            case .ioResult(let ioResult)?: reduceIOResult(state, ioResult)
            }
        }
        """
        let applyIO: DeclSyntax = """
        \(raw: access)func applyIOEffect(_ ioEffect: IOEffect) -> Effect<Action> {
            .run { send in
                for try await result in runIOEffect(ioEffect) {
                    await send(.ioResult(result))
                }
            }
        }
        """
        let apply: DeclSyntax = """
        \(raw: access)func apply(_ transition: Transition, to state: inout State) -> Effect<Action> {
            let (nextState, ioEffect) = transition
            if let nextState { state = nextState }
            return ioEffect.map { $0.asComposableEffect().extract(applyIOEffect(_:)) } ?? .none
        }
        """
        
        let forwardInputStatements = forwardInputMappers
            .map { $0.makeEffectSend(parentActionVariable: "input") }
            .joined(separator: "\n")
        
        let forwardIOResultStatements = forwardIOResultMappers
            .map { $0.makeEffectSend(parentActionVariable: "ioResult") }
            .joined(separator: "\n")


        let body: DeclSyntax
        // Auto-detect @ComposableStateMachine to include nestedBody
        if hasComposableStateMachine {
            body = """
                \(raw: access)var body: some Reducer<State, Action> {
                    nestedBody
                    Reduce { state, action in
                        // Apply parent's own reduction logic
                        let parentTransition = Self.reduce(state, action)
                        let parentEffect = apply(parentTransition, to: &state)

                        // Handle forwarding if mappers are present
                        var forwardedEffects: Effect<Action>
                        switch Action.map(action) {
                        case .input(let input)?:
                            var effects: [Effect<Action>] = []
                            \(raw: forwardInputStatements)
                            forwardedEffects = .merge(effects)
                        case .ioResult(let ioResult)?:
                            var effects: [Effect<Action>] = []
                            \(raw: forwardIOResultStatements)
                            forwardedEffects = .merge(effects)
                        case nil:
                            forwardedEffects = .none
                        }

                        return .merge(forwardedEffects, parentEffect)
                    }
                }
                """
        } else {
             body = """
                \(raw: access)var body: some Reducer<State, Action> {
                    Reduce { state, action in
                        // Apply parent's own reduction logic
                        let parentTransition = Self.reduce(state, action)
                        let parentEffect = apply(parentTransition, to: &state)

                        // Handle forwarding if mappers are present
                        var forwardedEffects: Effect<Action>
                        switch Action.map(action) {
                        case .input(let input)?:
                            var effects: [Effect<Action>] = []
                            \(raw: forwardInputStatements)
                            forwardedEffects = .merge(effects)
                        case .ioResult(let ioResult)?:
                            var effects: [Effect<Action>] = []
                            \(raw: forwardIOResultStatements)
                            forwardedEffects = .merge(effects)
                        case nil:
                            forwardedEffects = .none
                        }

                        return .merge(forwardedEffects, parentEffect)
                    }
                }
                """
        }

        return [reduce, applyIO, apply, body]
    }
}

private extension EffectRunnerAnalyzer {
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
    
    static func parseKeyPathArgument(from attribute: AttributeSyntax) throws -> String {
        guard let argument = attribute.arguments?.as(LabeledExprListSyntax.self)?.first?.expression else {
            throw MacroError.message(#"Attribute requires a KeyPath argument, e.g., (@ForwardInput(\.child))"#)
        }
        guard let keyPathExpr = argument.as(KeyPathExprSyntax.self) else {
            throw MacroError.message("Argument must be a KeyPath literal")
        }
        
        guard let component = keyPathExpr.components.last else {
            throw MacroError.message("KeyPath must have at least one component")
        }
        
        if let propertyComponent = component.as(KeyPathPropertyComponentSyntax.self) {
            return propertyComponent.declName.baseName.text
        }
        
        // Fallback: Just return the string representation of the component (e.g. "counter" or ".counter")
        let raw = component.trimmedDescription
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

private struct IOEffectCase {
    struct Parameter {
        let external: String?
        let internalName: String
        let type: String
        
        var signatureFragment: String {
            "_ \(internalName): \(type)"
        }
        
        var callArgument: String {
            internalName
        }
    }
    
    let name: String
    let parameters: [Parameter]
    
    var handlerName: String {
        "run" + name.prefix(1).uppercased() + name.dropFirst()
    }
    
    func makeHandlerRequirement(parentName: String) -> String {
        let params = parameters.map { $0.signatureFragment }.joined(separator: ", ")
        return "func \(handlerName)(\(params)) -> \(parentName).IOResultStream"
    }
    
    func makeSwitchCase() -> String {
        let bindings = parameters.map { "let \($0.internalName)" }.joined(separator: ", ")
        let patternSuffix = bindings.isEmpty ? "" : "(\(bindings))"
        let arguments = parameters.map { $0.callArgument }.joined(separator: ", ")
        let callSuffix = arguments.isEmpty ? "()" : "(\(arguments))"
        return "case .\(name)\(patternSuffix): self.\(handlerName)\(callSuffix)"
    }
}

private extension EnumDeclSyntax {
    func collectLeafCases() throws -> [IOEffectCase] {
        var results: [IOEffectCase] = []
        for member in memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                let caseName = element.name.text
                guard caseName != "merge", caseName != "concat" else { continue }
                let paramCount = element.parameterClause?.parameters.count ?? 0
                let parameters = element.parameterClause?.parameters.enumerated().map { index, param -> IOEffectCase.Parameter in
                    let type = param.type.trimmedDescription
                    let external = param.firstName?.text
                    let fallback = paramCount == 1 ? "arg" : "arg\(index + 1)"
                    let internalName = param.secondName?.text ?? external ?? fallback
                    return .init(external: external, internalName: internalName, type: type)
                } ?? []
                results.append(.init(name: caseName, parameters: parameters))
            }
        }
        return results
    }
    
    func containsCase(named name: String) -> Bool {
        for member in memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            if caseDecl.elements.contains(where: { $0.name.text == name }) {
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

private extension DeclSyntaxProtocol {
    func hasAttribute(named name: String) -> Bool {
        guard let attributes = self.asProtocol(WithAttributesSyntax.self)?.attributes else { return false }
        return attributes.contains { attr in
            guard let attribute = attr.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription == name
        }
    }

    func attribute(named name: String) -> AttributeSyntax? {
        guard let attributes = self.asProtocol(WithAttributesSyntax.self)?.attributes else { return nil }
        for element in attributes {
            if case let .attribute(attribute) = element, attribute.attributeName.trimmedDescription == name {
                return attribute
            }
        }
        return nil
    }
}

private extension DeclGroupSyntax {
    func hasAttribute(named name: String) -> Bool {
        for attr in attributes {
            if case let .attribute(attribute) = attr {
                let attrName = attribute.attributeName.trimmedDescription
                if attrName == name {
                    return true
                }
            }
        }
        return false
    }
}
