import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro for declaring nested features on the parent struct.
/// The `@ComposableStateMachine` macro reads this attribute.
public struct NestedFeatureMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker only - no expansion needed
        return []
    }
}
