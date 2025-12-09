import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct StateMachinePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ComposableEffectMembersMacro.self,
        EffectRunnerMacro.self
    ]
}

public struct ComposableEffectMembersMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw MacroError.message("@ComposableEffectMembers can only be attached to enums")
        }
        let caseDecls = enumDecl.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
        guard caseDecls.isNotEmpty else {
            throw MacroError.message("@ComposableEffectMembers requires at least one case")
        }
        
        let existingCaseNames = caseDecls.flatMap { $0.elements.map(\.name.text) }
        if existingCaseNames.contains("merge") || existingCaseNames.contains("concat") {
            throw MacroError.message("@ComposableEffectMembers cannot be applied to enums that already declare merge/concat cases")
        }
        
        let accessModifier = enumDecl.effectiveAccessModifier
        let accessPrefix = accessModifier.map { "\($0) " } ?? ""
        let composableCases: [DeclSyntax] = [
            "indirect case merge([Self])",
            "indirect case concat([Self])"
        ]
        
        let factories: [DeclSyntax] = [
            """
            static func merge(_ effects: Self...) -> Self {
                .merge(effects)
            }
            """,
            """
            static func concat(_ effects: Self...) -> Self {
                .concat(effects)
            }
            """
        ]
        
        let leafCaseNames = existingCaseNames.filter { $0 != "merge" && $0 != "concat" }
        let leafSwitchCases = leafCaseNames
            .map { "case .\($0): return .just(self)" }
            .joined(separator: "\n            ")
        
        let asComposableEffectDecl: DeclSyntax = """
        \(raw: accessPrefix)func asComposableEffect() -> ComposableEffect<Self> {
            switch self {
            case .merge(let effects):
                return .merge(effects.map { $0.asComposableEffect() })
            case .concat(let effects):
                return .concat(effects.map { $0.asComposableEffect() })
            \(raw: leafSwitchCases.isEmpty ? "" : leafSwitchCases)
            }
        }
        """
        
        return composableCases + factories + [asComposableEffectDecl]
    }
    
    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(EnumDeclSyntax.self) else {
            throw MacroError.message("@ComposableEffectMembers can only be attached to enums")
        }
        
        let typeDescription = type.trimmedDescription
        let protocolList = protocols.map { $0.trimmedDescription }.joined(separator: ", ")
        guard !protocolList.isEmpty else { return [] }
        
        let decl: DeclSyntax = "extension \(raw: typeDescription): \(raw: protocolList) { }"
        guard let ext = decl.as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }
}

private extension EnumDeclSyntax {
    var effectiveAccessModifier: String? {
        let supported = Set(["public", "package"])
        for modifier in modifiers {
            let name = modifier.name.text
            if supported.contains(name) {
                return name
            }
        }
        return nil
    }
}

extension Collection {
    var isNotEmpty: Bool { !isEmpty }
}

public enum MacroError: Error, CustomStringConvertible {
    case message(String)
    
    public var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}

private extension SyntaxProtocol {
    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

