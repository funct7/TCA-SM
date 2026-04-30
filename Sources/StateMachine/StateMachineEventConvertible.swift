import Foundation
import ComposableArchitecture

public protocol StateMachineEventConvertible<Input, IOResult>: CasePathable
where AllCasePaths == StateMachineEventAllCasePaths<Self> {
    associatedtype Input
    associatedtype IOResult
    
    static func input(_ value: Input) -> Self
    static func ioResult(_ value: IOResult) -> Self
    static func map(_ action: Self) -> StateMachineEvent<Input, IOResult>?
}
