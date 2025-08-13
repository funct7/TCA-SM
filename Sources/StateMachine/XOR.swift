import Foundation

public enum XOR<A, B> {
    case first(A)
    case second(B)
}

extension XOR : Sendable where A : Sendable, B : Sendable { }
