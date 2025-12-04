import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct StateMachinePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ComposableEffectMembersMacro.self
    ]
}

public struct ComposableEffectMembersMacro: MemberMacro {
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
        let accessModifier = enumDecl.effectiveAccessModifier
        return caseDecls.flatMap { decl in
            decl.elements.map { element in
                buildFunctionDecl(for: element, accessModifier: accessModifier)
            }
        }
    }
    
    private static func buildFunctionDecl(
        for element: EnumCaseElementSyntax,
        accessModifier: String?
    ) -> DeclSyntax {
        let name = element.name.text
        let parameterStrings: [(declaration: String, argument: String)]
        if let parameters = element.parameterClause?.parameters {
            parameterStrings = parameters.enumerated().map { index, parameter in
                parameter.render(index: index)
            }
        } else {
            parameterStrings = []
        }
        let parameterList = parameterStrings.map { $0.declaration }.joined(separator: ", ")
        let argumentList = parameterStrings.map { $0.argument }.joined(separator: ", ")
        let parametersClause = "(\(parameterList))"
        let argumentClause = argumentList.isEmpty ? "" : "(\(argumentList))"
        let accessPrefix = accessModifier.map { "\($0) " } ?? ""
        let functionDecl: DeclSyntax = """
        \(raw: accessPrefix)static func \(raw: name)\(raw: parametersClause) -> ComposableEffect<Self> {
            .just(.\(raw: name)\(raw: argumentClause))
        }
        """
        return functionDecl
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

private extension EnumCaseParameterSyntax {
    func render(index: Int) -> (declaration: String, argument: String) {
        let internalName = (secondName ?? firstName)?.text ?? "value\(index)"
        let typeDescription = type.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let externalName = firstName?.text
        let declaration: String
        if let externalName {
            if externalName == "_" {
                declaration = "_ \(internalName): \(typeDescription)"
            } else if secondName == nil {
                declaration = "\(externalName): \(typeDescription)"
            } else {
                declaration = "\(externalName) \(internalName): \(typeDescription)"
            }
        } else {
            declaration = "_ \(internalName): \(typeDescription)"
        }
        let argument: String
        if let externalName, externalName != "_" {
            argument = "\(externalName): \(internalName)"
        } else {
            argument = internalName
        }
        return (declaration, argument)
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

