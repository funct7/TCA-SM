import Foundation
import ComposableArchitecture

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

public extension ComposableEffect {
    
    typealias TCAEffect = ComposableArchitecture.Effect
    
    func extract<Action, Input, IOResult>(_ operation: @escaping (Effect) -> TCAEffect<Action>) -> TCAEffect<Action>
    where
    Action : StateMachineEventConvertible,
    Action : Sendable,
    Action.Input == Input,
    Action.IOResult == IOResult
    {
        switch self {
        case .just(let effect): operation(effect)
        case .merge(let effects): .merge(effects.map { $0.extract(operation) })
        case .concat(let effects): .concatenate(effects.map { $0.extract(operation) })
        }
    }
    
}
