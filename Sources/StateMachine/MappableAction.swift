// MARK: - XOR

public enum XOR<A, B>: Sendable {
    case first(A)
    case second(B)
}

// MARK: - MappableAction

public protocol MappableAction {
    associatedtype Input
    associatedtype IOResult

    static func input(_ value: Input) -> Self
    static func ioResult(_ value: IOResult) -> Self
    static func map(_ action: Self) -> XOR<Input, IOResult>?
}