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

extension StateMachineEvent: CasePaths.CasePathIterable { }
