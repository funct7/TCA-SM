import Foundation

indirect public enum ComposableEffect<Effect> {
    case just(Effect)
    case merge([Self])
    case concat([Self])
}

public extension ComposableEffect {
    
    static var none: Self { merge([]) }
    static func merge(_ effects: Effect...) -> Self { merge(effects.map(Self.just)) }
    static func merge(_ effects: Self...) -> Self { .merge(effects) }
    static func concat(_ effects: Effect...) -> Self { concat(effects.map(Self.just)) }
    static func concat(_ effects: Self...) -> Self { .concat(effects) }
    
}
