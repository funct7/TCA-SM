import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro for Input enum cases that forward their associated value as a child input.
/// The `@ComposableStateMachine` macro reads this attribute.
public struct ForwardValueMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker only - no expansion needed
        return []
    }
}
