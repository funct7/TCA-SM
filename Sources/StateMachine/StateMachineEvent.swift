// MARK: - StateMachineEvent

public enum StateMachineEvent<Input, IOResult>: Sendable, MappableAction {
    case input(Input)
    case ioResult(IOResult)

    public static func input(_ value: Input) -> StateMachineEvent<Input, IOResult> { .input(value) }
    public static func ioResult(_ value: IOResult) -> StateMachineEvent<Input, IOResult> { .ioResult(value) }

    public static func map(_ action: StateMachineEvent<Input, IOResult>) -> XOR<Input, IOResult>? {
        switch action {
        case .input(let input):
            return .first(input)
        case .ioResult(let result):
            return .second(result)
        }
    }
}