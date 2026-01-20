import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Generates `typealias Action = StateMachineEvent<Input, IOResult>` for StateMachine types.
public struct StateMachineMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Validate it's applied to a struct or actor
        guard declaration.is(StructDeclSyntax.self) || declaration.is(ActorDeclSyntax.self) else {
            throw MacroError.message("@StateMachine can only be attached to a struct or actor")
        }

        // Get access modifier
        let accessPrefix = declaration.effectiveAccessPrefix

        // Generate the Action typealias
        let actionTypealias: DeclSyntax = """
        \(raw: accessPrefix)typealias Action = StateMachineEvent<Input, IOResult>
        """

        return [actionTypealias]
    }
}

private extension DeclGroupSyntax {
    var effectiveAccessPrefix: String {
        for modifier in modifiers {
            let text = modifier.name.text
            if text == "public" || text == "package" {
                return text + " "
            }
        }
        return ""
    }
}
