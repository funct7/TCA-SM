import Foundation

public protocol ComposableEffectConvertible {
    /// Lift the current effect into a composable representation.
    func asComposableEffect() -> ComposableEffect<Self>
}
