import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct EffectRunnerMacro: MemberMacro, MemberAttributeMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let info = try EffectRunnerAnalyzer.analyze(declaration: declaration)
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
        if enumDecl.hasAttribute(named: "ComposableEffect") {
            return []
        }
        return ["@ComposableEffect"]
    }
}

private struct EffectRunnerAnalyzer {
    let parentName: String
    let ioEffectCases: [IOEffectCase]
    let parentDecl: DeclGroupSyntax
    
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
            throw MacroError.message("@EffectRunner can only be attached to a struct or actor")
        }
        guard let ioEffectEnum = declaration.memberBlock.members
            .compactMap({ $0.decl.as(EnumDeclSyntax.self) })
            .first(where: { $0.name.text == "IOEffect" }) else {
            throw MacroError.message("@EffectRunner requires a nested enum named IOEffect")
        }
        if ioEffectEnum.containsCase(named: "merge") || ioEffectEnum.containsCase(named: "concat") {
            throw MacroError.message("@EffectRunner should not be used when IOEffect already declares merge/concat")
        }
        let cases = try ioEffectEnum.collectLeafCases()
        return .init(parentName: parentName, ioEffectCases: cases, parentDecl: parentDecl)
    }
    
    func makeRunIOEffect() -> DeclSyntax {
        let leafSwitchCases = ioEffectCases
            .map { $0.makeSwitchCase() }
            .joined(separator: "\n        ")
        let access = accessPrefix
        return """
        \(raw: access)func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream {
            switch ioEffect {
            case .merge:
                return .init { $0.finish() }
            case .concat:
                return .init { $0.finish() }
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
        let body: DeclSyntax = """
        \(raw: access)var body: some Reducer<State, Action> {
            Reduce { state, action in
                let transition = Self.reduce(state, action)
                return apply(transition, to: &state)
            }
        }
        """
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
        let callSuffix = arguments.isEmpty ? "" : "(\(arguments))"
        return "case .\(name)\(patternSuffix): return self.\(handlerName)\(callSuffix)"
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
}
