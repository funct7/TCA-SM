import Foundation

public enum XOR<A, B> {
    case a(A)
    case b(B)
}

extension XOR : Sendable where A : Sendable, B : Sendable { }
