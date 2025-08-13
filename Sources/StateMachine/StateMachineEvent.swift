// MARK: - StateMachineEvent

public enum StateMachineEvent<Input, IOResult>: Sendable {
    case input(Input)
    case ioResult(IOResult)
}