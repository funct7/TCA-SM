# TCA-SM: State Machine Extension for The Composable Architecture

## Overview

TCA-SM enforces a functional core/imperative shell architecture in applications built with The Composable Architecture. It uses type-level constraints to physically separate pure state-transition logic from side effects, making architectural violations impossible rather than merely discouraged.

## Core Architecture

### StateMachine Protocol

The `StateMachine` protocol is the heart of TCA-SM. It formalizes the separation of concerns between pure state transitions and effectful I/O operations.

```swift
public protocol StateMachine: Reducer {
    associatedtype Input: Sendable
    associatedtype IOEffect: Sendable
    associatedtype IOResult: Sendable
    typealias IOResultStream = AsyncStream<IOResult>
    typealias Transition = (State?, IOEffect?)

    static func reduceInput(_ state: State, _ input: Input) -> Transition
    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition
    func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream
}
```

**Key Changes from older versions:**

- `EffectSequence` has been replaced by `IOResultStream`, which is a type alias for `AsyncStream<IOResult>`. This simplifies the protocol by standardizing on a concrete async sequence type.
- `runIOEffect` now returns an `IOResultStream`, an `AsyncStream` of results, allowing an effect to produce multiple values over time.

### Architectural Constraints

- **Static `reduce` methods**: `reduceInput` and `reduceIOResult` are static, ensuring they are pure functions with no access to dependencies or instance state.
- **Instance `runIOEffect` method**: This method is where side effects live. It has access to the feature's dependencies (e.g., API clients, databases) via `self`.
- **`Transition` tuple**: The `(State?, IOEffect?)` tuple returned by reducers decouples state calculation from effect execution. The new state is calculated first, and *then* the optional effect is run by the TCA runtime.

### Handling Effects and Results

The `runIOEffect` function is the designated place for all side effects. It takes an `IOEffect` and returns a stream of `IOResult` values.

```swift
struct Feature: StateMachine {
    @Dependency(\.apiClient) var apiClient

    // ... State, Input, IOEffect, IOResult ...

    func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream {
        switch ioEffect {
        case .fetchData:
            // Use the .single helper for one-shot operations
            return .single {
                await .fetchResponse(apiClient.fetchData())
            }
        case .subscribeToUpdates:
            // Return a long-lived stream for subscriptions
            return IOResultStream { continuation in
                let cancellable = apiClient.observeUpdates { result in
                    continuation.yield(.update(result))
                }
                continuation.onTermination = { _ in cancellable.cancel() }
            }
        case .logAnalytics:
            // For fire-and-forget effects, return an empty stream
            analytics.log("event")
            return .init { $0.finish() }
        }
    }
}
```

#### `AsyncStream.single` Helper

For effects that produce a single result (like a network request), you can use the `AsyncStream.single` helper, which is included in the library. It creates a stream that asynchronously produces one element and then finishes.

### Transition Helpers

A set of static helper functions are provided on `StateMachine` to make creating `Transition` values more expressive.

```swift
extension StateMachine {
    static var undefined: Transition { (nil, nil) } // No-op, useful for switch statements
    static var identity: Transition { (nil, nil) }  // Alias for undefined
    static func nextState(_ state: State) -> Transition { (state, nil) } // State change, no effect
    static func run(_ effect: IOEffect) -> Transition { (nil, effect) } // Effect, no state change
    static func transition(_ state: State, _ effect: IOEffect) -> Transition { (state, effect) } // State change and effect
    static func unsafe(_ action: @escaping () -> Void) -> Transition { action(); return (nil, nil) } // Escape hatch for logging, etc.
}
```

## Action Mapping

The `StateMachineEventConvertible` protocol allows you to integrate `StateMachine` logic into a standard TCA `Action` enum, enabling gradual adoption and composition with other TCA features.

```swift
protocol StateMachineEventConvertible {
    associatedtype Input
    associatedtype IOResult

    static func input(_: Input) -> Self
    static func ioResult(_: IOResult) -> Self
    static func map(_ action: Self) -> StateMachineEvent<Input, IOResult>?
}
```

**Example:**

```swift
enum Action: StateMachineEventConvertible {
    // State machine events
    case input(Input)
    case ioResult(IOResult)
    // Other events
    case child(ChildFeature.Action)
    case onAppear

    static func map(_ action: Self) -> StateMachineEvent<Input, IOResult>? {
        switch action {
        case .input(let input): return .input(input)
        case .ioResult(let result): return .ioResult(result)
        default: return nil // Other cases handled by a different reducer
        }
    }
}
```

## Composing Effects

While reducers can only return a single `IOEffect` at a time, this `IOEffect` can be a composition of multiple smaller effects. TCA-SM provides macros to make this composition ergonomic.

### `@ComposableEffect` Macro

Add the `@ComposableEffect` attribute to your `IOEffect` enum. The macro synthesizes:
1.  `merge([Self])` and `concat([Self])` cases.
2.  Static factory methods `.merge(Self...)` and `.concat(Self...)` for convenience.
3.  An `asComposableEffect()` method to convert the enum into a `ComposableEffect` type used by the runtime.

```swift
@ComposableEffect
enum IOEffect {
    case fetch(Int)
    case log(String)
}

// In your reducer:
static func reduceInput(_ state: State, _ input: Input) -> Transition {
    switch input {
    case .buttonTapped:
        // Run effects in parallel
        return run(.merge(.fetch(1), .log("fetching")))
    case .anotherButtonTapped:
        // Run effects sequentially
        return run(.concat(.log("step 1"), .log("step 2")))
    }
}
```

### `@ComposableEffectRunner` Macro

For a fully automated setup, apply the `@ComposableEffectRunner` attribute to your `StateMachine` feature type (struct or actor). It does several things:

1.  **Auto-applies `@ComposableEffect`**: It ensures the nested `IOEffect` enum is composable.
2.  **Generates Reducer Body**: It synthesizes the `reduce`, `applyIOEffect`, `apply`, and `body` properties required to run the state machine, including logic to handle composed effects.
3.  **Generates `EffectRunner` Protocol**: It creates a private `{FeatureName}.EffectRunner` protocol with a `run<CaseName>` method for each case in your `IOEffect` enum.
4.  **Generates `runIOEffect` Dispatcher**: It implements the main `runIOEffect` method for you, which dispatches each effect case to the corresponding `EffectRunner` method.

You conform your feature to the generated `EffectRunner` protocol and implement the per-case methods.

**Minimal Example:**
```swift
@ComposableEffectRunner
struct Feature: StateMachine {
    struct State: Equatable { var count = 0 }
    enum Input { case tap }
    enum IOEffect { // @ComposableEffect is added automatically
        case fetch(Int)
        case log(String)
    }
    typealias IOResult = TaskResult<String>
    typealias Action = StateMachineEvent<Input, IOResult>

    static func reduceInput(_ state: State, _ input: Input) -> Transition {
        run(.concat(.log("Tapped"), .fetch(state.count)))
    }

    static func reduceIOResult(_ state: State, _ result: IOResult) -> Transition {
        // Handle fetch result
        return nextState(state)
    }
}

// Conform to the synthesized protocol
extension Feature: Feature.EffectRunner {
    func runFetch(_ value: Int) -> IOResultStream {
        .single {
            // ... perform fetch and return result
            .success("Result")
        }
    }

    func runLog(_ message: String) -> IOResultStream {
        print(message)
        return .init { $0.finish() } // No result
    }
}
```

## Composing State Machines

The `@ComposableEffectRunner` macro provides a powerful mechanism for composing a `StateMachine` feature within a parent reducer, just like any other TCA reducer.

### Embedding a StateMachine in a Parent Feature

This is the most common composition pattern. The parent is a standard TCA `Reducer`, and the child is a `StateMachine`.

**1. Prepare the Child StateMachine**

To make a `StateMachine` embeddable, add `@ComposableEffectRunner(isBodyComposable: true)` to it. This tells the macro to generate a `body` property that allows it to be composed in another reducer's `body`.

```swift
@ComposableEffectRunner(isBodyComposable: true) // Crucial for composition
struct ChildFeature: StateMachine {
    // ... State, Input, IOEffect, IOResult, Action
    // ... Reducer logic and EffectRunner conformance
    // NO 'body' property is needed here; the macro generates it.
}
```

**2. Create the Parent Reducer**

The parent can be any standard TCA `Reducer`. It holds the child's state and scopes actions to it.

```swift
// ParentFeature is a standard Reducer, not a StateMachine
struct ParentFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        var child: ChildFeature.State
        // ... other parent state
    }

    enum Action {
        case child(ChildFeature.Action)
        // ... other parent actions
    }

    var body: some Reducer<State, Action> {
        // Scope to the child StateMachine. This uses the 'body'
        // generated by @ComposableEffectRunner on ChildFeature.
        Scope(state: \.child, action: \.child) {
            ChildFeature()
        }

        // Parent's own reduction logic
        Reduce { state, action in
            switch action {
            // The parent can observe results from the child
            case .child(.ioResult(let result)):
                print("Child produced a result: \(result)")
                // Parent can change its own state or run its own effects
                // in response to the child's output.
                return .none

            default:
                return .none
            }
        }
    }
}
```

**Key Points:**
- **Parent:** A standard `Reducer`. It uses `Scope` to embed the child.
- **Child:** A `StateMachine` with `@ComposableEffectRunner(isBodyComposable: true)`.
- **Communication:** The parent can send actions to the child and observe the child's `IOResult` to react to its outputs.

### Having a StateMachine as a Parent (`nestedBody`)

It's less common, but a `StateMachine` can also act as a parent and contain other reducers.

When you use `@ComposableEffectRunner(isBodyComposable: true)`, the macro generates a `body` that looks like this:

```swift
var body: some Reducer<State, Action> {
    nestedBody // <--- You must provide this
    Reduce { state, action in
        // ... state machine logic ...
    }
}
```

You must then implement the `nestedBody` property on your `StateMachine` to hold the child reducers.

```swift
@ComposableEffectRunner(isBodyComposable: true)
struct ParentStateMachine: StateMachine {
    // ... StateMachine implementation ...

    // You provide nestedBody to compose children
    var nestedBody: some Reducer<State, Action> {
        Scope(state: \.child, action: \.child) {
            SomeOtherChildFeature()
        }
    }
}
```

## Testing

Testing is a core strength of the architecture promoted by TCA-SM.

### Testing Pure Reducers

Because `reduceInput` and `reduceIOResult` are static, pure functions, you can test state transitions directly and synchronously, without needing a `TestStore`.

```swift
func testLoginInput() {
    // Test that the correct state change and effect are requested
    let (state, effect) = Login.reduceInput(.init(), .didTapLoginButton)
    XCTAssertEqual(state?.isLoading, true)
    XCTAssertEqual(effect, .authenticate("user", "pass"))
}
```

For integration tests, you can use a `TestStore` from the `ComposableArchitecture` library. This is especially useful for `StateMachine`s that do not use `@ComposableEffectRunner`. You can mock the `runIOEffect` by providing a test-specific implementation.

```swift
func testFullFlow() async {
    // Create a test-specific version of the feature for mocking effects
    struct TestFeature: StateMachine {
        // Implement the protocol...
        
        // Override runIOEffect to return mock data
        func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream {
            switch ioEffect {
            case .fetch:
                return .single { .success("mock data") }
            default: return .init { $0.finish() }
            }
        }
    }

    let store = TestStore(initialState: TestFeature.State()) {
        TestFeature()
    }

    await store.send(.input(.didTapButton)) {
        $0.isLoading = true
    }
    await store.receive(\.ioResult.success) {
        $0.data = "mock data"
        $0.isLoading = false
    }
}
```

### Testing Composable Effect Runners

When using `@ComposableEffectRunner`, testing becomes even simpler. You don't need to create a separate test-specific feature type. The recommended approach is to leverage TCA's dependency injection system.

Your `EffectRunner` methods should use dependencies from the `@Dependency` property wrapper to perform their work.

```swift
// In your feature
@ComposableEffectRunner
struct Feature: StateMachine {
    @Dependency(\.apiClient) var apiClient
    // ...

    // EffectRunner conformance
    func runFetchData() -> IOResultStream {
        .single {
            await .dataResponse(self.apiClient.fetchData())
        }
    }
}
```

In your test, you can then use `TestStore` to override the dependency with a mock version. This allows you to control the data returned by the effect and assert that the correct state changes occur.

```swift
import ComposableArchitecture

@MainActor
func testFeatureWithRunner() async {
    let store = TestStore(initialState: Feature.State()) {
        Feature()
    } withDependencies: {
        // Override the dependency for this test
        $0.apiClient.fetchData = { "mocked data" }
    }

    await store.send(.input(.didTapButton)) {
        // State changes from the input
        $0.isLoading = true
    }
    
    // Assert that the IOResult from the mocked dependency
    // is received and causes the correct state change.
    await store.receive(\.ioResult.dataResponse) {
        $0.isLoading = false
        $0.data = "mocked data"
    }
}
```
This approach is powerful because it allows you to test the *real* implementation of your `EffectRunner` methods, with only the external dependencies swapped out.

## Migration

### From TCA to TCA-SM

**TCA Style:**
```swift
case .buttonTapped:
    state.isLoading = true
    return .run { send in
        let result = await apiClient.fetchData()
        await send(.dataLoaded(result))
    }
```

**TCA-SM Style:**
```swift
// Reducer (Pure)
static func reduceInput(_ state: State, _ input: Input) -> Transition {
    case .buttonTapped:
        return transition(.init(isLoading: true), .fetchData)
}

// Effect Runner (Impure)
func runFetchData() -> IOResultStream {
    .single {
        .dataLoaded(await apiClient.fetchData())
    }
}
```
This refactoring isolates the side effect (`apiClient.fetchData`) from the state transition logic, improving testability and clarity.
