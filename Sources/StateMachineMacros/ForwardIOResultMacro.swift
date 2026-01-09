import SwiftSyntax
import SwiftSyntaxMacros

public struct ForwardIOResultMacro: PeerMacro {
    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol,
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.DeclSyntax] {
        // This macro is primarily a marker. It doesn't expand into new declarations.
        // Its purpose is to hold the KeyPath argument which the ComposableEffectRunner
        // macro will later inspect.
        return []
    }
}
