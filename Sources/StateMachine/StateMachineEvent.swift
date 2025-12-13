import Foundation
import ComposableArchitecture

@dynamicMemberLookup
public enum StateMachineEvent<Input, IOResult> {
    case input(Input)
    case ioResult(IOResult)
}

extension StateMachineEvent : Sendable where Input : Sendable, IOResult : Sendable { }

extension StateMachineEvent : StateMachineEventConvertible {
    
    public static func map(_ action: Self) -> StateMachineEvent<Input, IOResult>? { action }
    
}

public extension StateMachineEvent {
    
    struct AllCasePaths: CasePaths.CasePathReflectable, Sendable, Sequence {
        
        public subscript(
            root: StateMachineEvent<Input, IOResult>
        ) -> CasePaths.PartialCaseKeyPath<StateMachineEvent<Input, IOResult>> {
            if root.is(\.input) { return \.input }
            if root.is(\.ioResult) { return \.ioResult }
            return \.never
        }
        
        public var input: CasePaths.AnyCasePath<StateMachineEvent<Input, IOResult>, Input> {
            ._$embed(StateMachineEvent.input) {
                guard case let .input(v0) = $0 else { return nil }
                return v0
            }
        }
        
        public var ioResult: CasePaths.AnyCasePath<StateMachineEvent<Input, IOResult>, IOResult> {
            ._$embed(StateMachineEvent.ioResult) {
                guard case let .ioResult(v0) = $0 else { return nil }
                return v0
            }
        }
        
        public func makeIterator(
        ) -> Swift.IndexingIterator<[CasePaths.PartialCaseKeyPath<StateMachineEvent<Input, IOResult>>]> {
            var allCasePaths: [CasePaths.PartialCaseKeyPath<StateMachineEvent<Input, IOResult>>] = []
            allCasePaths.append(\.input)
            allCasePaths.append(\.ioResult)
            return allCasePaths.makeIterator()
        }
        
    }
    
    static var allCasePaths: AllCasePaths { AllCasePaths() }
    
}

extension StateMachineEvent: CasePaths.CasePathable, CasePaths.CasePathIterable { }
