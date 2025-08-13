import Foundation

public enum StateMachineEvent<Input, IOResult> {
    case input(Input)
    case ioResult(IOResult)
}

extension StateMachineEvent : Sendable where Input : Sendable, IOResult : Sendable { }

extension StateMachineEvent : MappableAction {
    
    public static func map(_ action: Self) -> XOR<Input, IOResult>? {
        switch action {
        case .input(let input): .a(input)
        case .ioResult(let result): .b(result)
        }
    }
    
}
