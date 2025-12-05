# TCA-SM: State Machine Extension for The Composable Architecture

## Overview

TCA-SM enforces functional core/imperative shell architecture through type-level constraints in The Composable Architecture. It physically separates pure state transitions from IO effects, making architectural violations impossible rather than merely discouraged.

## Core Architecture

### StateMachine Protocol

```swift
protocol StateMachine : Reducer {
    associatedtype Input : Sendable
    associatedtype IOEffect : Sendable
    associatedtype IOResult : Sendable

    typealias Transition = (State?, ComposableEffect<IOEffect>)

    static func reduceInput(_ state: State, _ input: Input) -> Transition
    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition
    func runIOEffect(_ ioEffect: IOEffect) async -> IOResult?
    func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream
}
```

**Architectural Constraints**:

- **Static reduce methods**: Enforce purity—no access to dependencies or instance state
- **Dual runIOEffect overloads**: Single-result helper keeps basic IO ergonomic; stream overload powers long-lived effects without exposing continuations. Internally we merge both sources via `AsyncAlgorithms.merge`, so implement whichever fits the effect and they automatically co-exist.
- **Composable Transition tuple**: Prevents coupling state calculation with effect execution while supporting concat/merge composition

### Why Static vs Instance Methods

```swift
struct MyFeature : StateMachine {
    @Dependency(\\.locationManager) var locationManager  // Available in runIOEffect
    let apiService: any APIService                      // Available in runIOEffect

    // Static = pure, no dependencies access
    static func reduceInput(_ state: State, _ input: Input) -> Transition { ... }

    // Instance = can access dependencies for side effects
    func runIOEffect(_ ioEffect: IOEffect) async -> IOResult? {
        await apiService.fetchData()  // ✅ Can access instance properties
    }
}

### Streaming IOEffects

Use the stream overload when an effect needs to emit more than one `IOResult` over time. The framework merges that stream with the synthesized single-result stream, so `.fetch` can remain a one-off effect while `.print` (or similar) can emit multiple values without boilerplate.

```swift
func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream {
    guard case .locationUpdates = ioEffect else {
        return IOResultStream { $0.finish() }
    }

    return IOResultStream { continuation in
        let task = Task {
            for await reading in locationManager.updates() {
                guard !Task.isCancelled else { break }
                continuation.yield(.location(.success(reading)))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

```
```

## Action Mapping Pattern

### StateMachineEventConvertible Protocol

```swift
protocol StateMachineEventConvertible {
    associatedtype Input
    associatedtype IOResult

    static func input(_: Input) -> Self
    static func ioResult(_: IOResult) -> Self
    static func map(_ action: Self) -> StateMachineEvent<Input, IOResult>?
}
```

Enables gradual adoption—mix StateMachine actions with standard TCA actions:

```swift
enum Action: StateMachineEventConvertible {
    case input(Input)
    case ioResult(IOResult)
    case childAction(ChildFeature.Action)  // Non-SM reducer

    static func map(_ action: Self) -> StateMachineEvent<Input, IOResult>? {
        switch action {
        case .input(let input): .input(input)
        case .ioResult(let result): .ioResult(result)
        case .childAction: nil  // Handled separately
        }
    }
}
```

## Transition Helpers

```swift
extension StateMachine {
    static var undefined: Transition { (nil, .none) }
    static var identity: Transition { (nil, .none) }
    static func nextState(_ state: State) -> Transition { (state, .none) }
    static func run(_ effect: IOEffect) -> Transition { (nil, .just(effect)) }
    static func run(_ effect: ComposableEffect<IOEffect>) -> Transition { (nil, effect) }
    static func transition(_ state: State, effect: IOEffect) -> Transition { (state, .just(effect)) }
    static func transition(_ state: State, effect: ComposableEffect<IOEffect>) -> Transition { (state, effect) }
    static func unsafe(_ action: @escaping () -> Void) -> Transition { action(); return (nil, .none) }
}
```

### ComposableEffect Macro

Add the `@ComposableEffectMembers` attribute to any effect enum to synthesize scoped helpers that lift enum cases into `ComposableEffect` values. This keeps reducer code terse even when mixing nested combinators:

```swift
@ComposableEffectMembers
enum IOEffect {
    case fetch(Int)
    case print(Int)
}

static func reduceInput(_ state: State, _ input: Input) -> Transition {
    switch input {
    case .numberFactButtonTapped:
        run(.concat(
            .fetch(state.count),
            .merge(
                .print(state.count),
                .print(state.count * 2)
            )
        ))
    }
}
```

The macro-generated functions honor the enum's access control, so `public enum` cases yield `public static func fetch(...) -> ComposableEffect` helpers that downstream modules can call without wrapping cases in `.just` manually.

## Key Design Principles

### 1. Effect Abstraction

Abstract implementation details behind semantic boundaries. IO runners perform side effects and surface outcomes as `IOResult` values without making decisions:

```swift
enum IOEffect {
    case authenticate(username: String, password: String)
}

enum IOResult {
    case loginResponse(Result<Token, NetworkError>)
    case profileResponse(Result<Profile, NetworkError>)
}

func runIOEffect(_ effect: IOEffect) -> IOResultStream {
    guard case let .authenticate(username, password) = effect else {
        return IOResultStream { $0.finish() }
    }

    return IOResultStream { continuation in
        let task = Task {
            do {
                let token = try await api.login(username, password)
                continuation.yield(.loginResponse(.success(token)))
            } catch {
                continuation.yield(.loginResponse(.failure(.network(error))))
                continuation.finish()
                return
            }

            do {
                let profile = try await api.fetchProfile()
                continuation.yield(.profileResponse(.success(profile)))
            } catch {
                continuation.yield(.profileResponse(.failure(.network(error))))
            }

            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

### 2. State-Driven Cancellation

State transitions implicitly manage effect lifecycle:

```swift
static func reduceInput(_ state: State, _ input: Input) -> Transition {
    switch (state, input) {
    case (.loading, .search(let newQuery)):
        // Previous search implicitly cancelled by state change
        return transition(.loading(query: newQuery), effect: .search(newQuery))
    }
}
```

### 3. Multi-Step Operations as State Phases

```swift
enum State {
    case ready
    case authenticating
    case fetchingUser(token: Token)
    case fetchingPosts(user: User, token: Token)
    case complete(user: User, posts: [Post])
    case failed(Error)
}
```

### 4. Deterministic Error Handling

All errors flow through IOResult:

```swift
enum IOResult {
    case dataLoaded(Result<Data, NetworkError>)
    case userSaved(Result<Void, DatabaseError>)
}

// Never:
func runIOEffect(_ effect: IOEffect) throws -> IOResult?  // ❌ keep IO errors inside IOResult
```

### 5. Decision Logic in Reducers

```swift
// Wrong: Logic in IO
func runIOEffect(_ effect: IOEffect) async -> IOResult? {
    switch effect {
    case .fetchData(let useCache):
        if useCache && cache.hasData {  // ❌ Decision in IO
            return .dataFetched(cache.data)
        }
        return nil
    }
}

// Correct: Logic in reducer
static func reduceInput(_ state: State, _ input: Input) -> Transition {
    case .load:
        if state.cacheValid {
            return nextState(.loaded(state.cachedData))  // ✅ Pure decision
        } else {
            return transition(.loading, effect: .fetchFreshData)
        }
}
```

## Integration Patterns

### Standard Body Implementation

```swift
var body: some Reducer<State, Action> {
    Reduce { state, action in
        let transition = Self.reduce(state, action)
        return apply(transition, to: &state)
    }
}
```

### Composed with Child Reducers

```swift
var body: some Reducer<State, Action> {
    // Child reducer scope
    Scope(state: \\.mapState, action: \\.mapAction) {
        MapFeature()
    }

    // Handle child interactions (can produce child effects)
    Reduce { state, action in
        switch action {
        case .input(let input):
            Self.reduceInput(state, input).map(Action.mapAction)
        case .ioResult(let ioResult):
            Self.reduceIOResult(state, ioResult).map(Action.mapAction)
        case .mapAction(let mapAction):
            reduceMapEvent(state, mapAction).map(Action.mapAction)
        }
    }

    // StateMachine logic (produces IO effects)
    Reduce { state, action in
        let transition = Self.reduce(state, action)
        return apply(transition, to: &state)
    }
}
```

## Testing Strategy

### Pure Function Testing

```swift
func testStateTransitions() {
    // Synchronous, deterministic tests
    let result = Feature.reduceInput(.idle, .load)
    XCTAssertEqual(result.0, .loading)
    XCTAssertEqual(result.1, .fetchData)
}
```

### IO Mocking

```swift
struct MockFeature: StateMachine {
    let mockResults: [IOEffect: IOResult]

    func runIOEffect(_ effect: IOEffect) async -> IOResult? {
        mockResults[effect]
    }
}
```

## Migration Patterns

### From TCA

```swift
// TCA Style
case .buttonTapped:
    state.isLoading = true
    return .run { send in
        do {
            let data = try await api.fetch()
            await send(.dataLoaded(data))
        } catch {
            await send(.loadFailed(error))
        }
    }

// TCA-SM Style
static func reduceInput(_ state: State, _ input: Input) -> Transition {
    case .buttonTapped:
        return transition(.loading, effect: .fetchData)
}

func runIOEffect(_ effect: IOEffect) async -> IOResult? {
    switch effect {
    case .fetchData:
        do {
            let data = try await api.fetch()
            return .dataFetched(data)
        } catch {
            return .fetchFailed(error)
        }
    }
}

// When an effect truly emits multiple values, override
// override runIOEffect(_: ) -> IOResultStream instead of wrapping the single result.
```

## Migration Patterns

### From TCA to TCA-SM

```swift
// TCA Style
case .buttonTapped:
    state.isLoading = true
    return .run { send in
        do {
            let data = try await api.fetch()
            await send(.dataLoaded(data))
        } catch {
            await send(.loadFailed(error))
        }
    }

// TCA-SM Style
static func reduceInput(_ state: State, _ input: Input) -> Transition {
    case .buttonTapped:
        return transition(.loading, effect: .fetchData)
}

func runIOEffect(_ effect: IOEffect) async -> IOResult? {
    switch effect {
    case .fetchData:
        do {
            let data = try await api.fetch()
            return .dataFetched(data)
        } catch {
            return .fetchFailed(error)
        }
    }
}
```

## Common Patterns

### Resource Validation

```swift
case .purchase:
    if state.points < cost {
        return nextState(withVar(state, \\.showInsufficientPointsAlert, true))
    } else {
        return transition(
            withVar(state, \\.points, state.points - cost),
            effect: .completePurchase
        )
    }
```

### Retry Logic

```swift
static func reduceIOResult(_ state: State, _ result: IOResult) -> Transition {
    switch (state, result) {
    case (.active(let count), .requestFailed(let error)):
        if count < 3 {
            return transition(.active(retryCount: count + 1), effect: .retryRequest)
        } else {
            return nextState(.failed(error, retryCount: count))
        }
    }
}
```

## Architectural Trade-offs

**Enforce Through Types**:

- Static methods prevent dependency access in pure functions
- Transition tuple prevents effect execution during state calculation
- IOResult wrapping makes error handling deterministic

**Concurrency Model**:

- Single IOEffect per transition (compose through state, not effects)
- Cancellation implicit in state transitions
- Background operations tracked in State or instance variables

**When to Use**:

- Complex state machines with clear phases
- Business logic requiring high testability
- Systems where maintenance cost > initial development speed

**When to Avoid**:

- Simple UI-only features
- Prototypes requiring rapid iteration
- Features primarily about TCA child composition
