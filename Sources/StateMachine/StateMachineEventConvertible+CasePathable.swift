import ComposableArchitecture

public struct StateMachineEventAllCasePaths<Root: StateMachineEventConvertible>: CasePathReflectable, Sendable, Sequence {

    public subscript(root: Root) -> PartialCaseKeyPath<Root> {
        switch Root.map(root) {
        case .input?: \.input
        case .ioResult?: \.ioResult
        case nil: \.never
        }
    }

    public var input: AnyCasePath<Root, Root.Input> {
        ._$embed(Root.input) {
            guard case let .input(input) = Root.map($0) else { return nil }
            return input
        }
    }

    public var ioResult: AnyCasePath<Root, Root.IOResult> {
        ._$embed(Root.ioResult) {
            guard case let .ioResult(ioResult) = Root.map($0) else { return nil }
            return ioResult
        }
    }

    public func makeIterator() -> IndexingIterator<[PartialCaseKeyPath<Root>]> {
        [\.input, \.ioResult].makeIterator()
    }

}

public extension StateMachineEventConvertible {
    
    static var allCasePaths: StateMachineEventAllCasePaths<Self> {
        StateMachineEventAllCasePaths()
    }
    
}

public extension StateMachineEventConvertible where IOResult == Never {
    
    static func ioResult(_ value: Never) -> Self { }
    
}
