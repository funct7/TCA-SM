import Foundation

public enum StateMachineEvent<Input, IOResult> {
    case input(Input)
    case ioResult(IOResult)
}

extension StateMachineEvent : Sendable where Input : Sendable, IOResult : Sendable { }

extension StateMachineEvent : MappableAction {
    public static func input(_ value: Input) -> StateMachineEvent<Input, IOResult> { .input(value) }
    public static func ioResult(_ value: IOResult) -> StateMachineEvent<Input, IOResult> { .ioResult(value) }
    
    public static func map(_ action: StateMachineEvent<Input, IOResult>) -> XOR<Input, IOResult>? {
        switch action {
        case .input(let input): .first(input)
        case .ioResult(let result): .second(result)
        }
    }
}
