import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro for Input/IOResult enum cases that forward to child features.
/// The `@ComposableStateMachine` macro reads this attribute.
public struct ForwardMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker only - no expansion needed
        return []
    }
}
