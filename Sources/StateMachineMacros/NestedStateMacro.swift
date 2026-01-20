import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro for State properties containing nested feature state.
/// The `@ComposableStateMachine` macro reads this attribute.
public struct NestedStateMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker only - no expansion needed
        return []
    }
}
