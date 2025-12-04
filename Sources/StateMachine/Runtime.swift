import Foundation
import ComposableArchitecture

// MARK: - Runtime

@available(iOS 16, *)
public typealias Runtime<SM> = Store<SM.State, SM.Input>
where
SM : StateMachine,
SM.Action : StateMachineEventConvertible

@available(iOS 16, *)
public extension Runtime {
    
    static func make<SM>(
        initialState: @autoclosure () -> SM.State,
        @ReducerBuilder<SM.State, SM.Action> stateMachine: () -> SM,
        withDependencies prepareDependencies: ((inout DependencyValues) -> Void)? = nil
    ) -> Runtime<SM>
    where SM : StateMachine,
          SM.State == State,
          SM.Action : StateMachineEventConvertible,
          SM.Action == Action,
          Action.Input == SM.Input
    {
        Store(
            initialState: initialState(),
            reducer: stateMachine,
            withDependencies: prepareDependencies
        )
        .scope(state: \.self, action: SM.Action.input(_:))
    }
    
}

// MARK: - Runtimes

@available(iOS 16, *)
public enum Runtimes<SM>
where SM : StateMachine,
      SM.Action : StateMachineEventConvertible,
      SM.Action.Input == SM.Input,
      SM.Action.IOResult == SM.IOResult
{ }

@available(iOS 16, *)
public extension Runtimes {
    
    static func make(
        initialState: @autoclosure () -> SM.State,
        @ReducerBuilder<SM.State, SM.Action> stateMachine: () -> SM,
        withDependencies prepareDependencies: ((inout DependencyValues) -> Void)? = nil
    ) -> Runtime<SM>
    {
        Store<SM.State, SM.Action>(
            initialState: initialState(),
            reducer: stateMachine,
            withDependencies: prepareDependencies
        )
        .scope(state: \.self, action: SM.Action.input(_:))
    }
    
}

// MARK: - StandardRuntime

@available(iOS 16, *)
public typealias StandardRuntime<SM> = Runtime<SM>
where SM : StateMachine, SM.Action == StateMachineEvent<SM.Input, SM.IOResult>

@available(iOS 16, *)
public typealias StandardRuntimes<SM> = Runtimes<SM>
where
SM : StateMachine,
SM.Action == StateMachineEvent<SM.Input, SM.IOResult>
