import SwiftSyntax
import SwiftSyntaxMacros
import Foundation

public struct ForwardIOResultMacro: PeerMacro {
    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol,
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.DeclSyntax] {
        // Check if this is the new two-argument form: @ForwardIOResult(\IOResult.Cases.x, to: \Action.Cases.y)
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            // No arguments - invalid usage
            throw MacroError.message("@ForwardIOResult requires at least one argument")
        }
        
        let argumentList = Array(arguments)
        
        // Legacy mode: single argument, applied to a function - just a marker
        if argumentList.count == 1 {
            return []
        }
        
        // New extraction mode: two arguments (@ForwardIOResult(\IOResult.Cases.x, to: \Action.Cases.y))
        guard argumentList.count == 2 else {
            throw MacroError.message("@ForwardIOResult expects either 1 argument (legacy) or 2 arguments (extraction mode)")
        }
        
        // Parse second argument: must have label "to"
        guard argumentList[1].label?.text == "to" else {
            throw MacroError.message("@ForwardIOResult second argument must be labeled 'to:'")
        }
        let childActionCase = try parseKeyPathLastComponent(from: argumentList[1].expression)
        
        // Get the full keypath expression for the IOResult case (for use in generated code)
        let ioResultKeyPathExpr = argumentList[0].expression.trimmedDescription
        
        // Derive the forwarder property name from the child action case
        let forwarderName = "\(childActionCase)IOResultForwarder"
        
        // Detect access modifier from parent declaration
        let accessPrefix = detectAccessModifier(from: declaration)
        
        // Generate the partial reducer
        let reducer: DeclSyntax = """
            \(raw: accessPrefix)static var \(raw: forwarderName): some Reducer<State, Action> {
                Reduce { state, action in
                    guard case .ioResult(let ioResult) = Action.map(action),
                          let childIOResult = ioResult[case: \(raw: ioResultKeyPathExpr)] else {
                        return .none
                    }
                    return .send(.\(raw: childActionCase)(.ioResult(childIOResult)))
                }
            }
            """
        
        return [reducer]
    }
    
    private static func parseKeyPathLastComponent(from expression: ExprSyntax) throws -> String {
        guard let keyPathExpr = expression.as(KeyPathExprSyntax.self) else {
            throw MacroError.message("Argument must be a KeyPath literal")
        }
        
        guard let component = keyPathExpr.components.last else {
            throw MacroError.message("KeyPath must have at least one component")
        }
        
        if let propertyComponent = component.as(KeyPathPropertyComponentSyntax.self) {
            return propertyComponent.declName.baseName.text
        }
        
        // Fallback: return trimmed component text
        let raw = component.trimmedDescription
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
    
    private static func detectAccessModifier(from declaration: some DeclSyntaxProtocol) -> String {
        // Check if the declaration or its parent has public/package access
        if let withModifiers = declaration.asProtocol(WithModifiersSyntax.self) {
            for modifier in withModifiers.modifiers {
                let text = modifier.name.text
                if text == "public" || text == "package" {
                    return text + " "
                }
            }
        }
        return ""
    }
}
