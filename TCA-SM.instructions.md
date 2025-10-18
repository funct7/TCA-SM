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
    associatedtype EffectSequence : AsyncSequence where EffectSequence.Element == IOResult

    typealias Transition = (State?, IOEffect?)

    static func reduceInput(_ state: State, _ input: Input) -> Transition
    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition
    func runIOEffect(_ ioEffect: IOEffect) -> EffectSequence
}
```

**Architectural Constraints**:

- **Static reduce methods**: Enforce purity—no access to dependencies or instance state
- **Instance runIOEffect**: Enables dependency injection for side effects
- **Transition tuple**: Prevents coupling state calculation with effect execution

### Why Static vs Instance Methods

```swift
struct MyFeature : StateMachine {
    @Dependency(\\.locationManager) var locationManager  // Available in runIOEffect
    let apiService: any APIService                      // Available in runIOEffect

    // Static = pure, no dependencies access
    static func reduceInput(_ state: State, _ input: Input) -> Transition { ... }

    // Instance = can access dependencies for side effects
    func runIOEffect(_ ioEffect: IOEffect) -> EffectSequence {
        AsyncStream { continuation in
            Task {
                _ = await apiService.fetchData()  // ✅ Can access instance properties
                continuation.finish()
            }
        }
    }
}
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
    static var undefined: Transition { (nil, nil) }
    static var identity: Transition { (nil, nil) }
    static func nextState(_ state: State) -> Transition { (state, nil) }
    static func run(_ effect: IOEffect) -> Transition { (nil, effect) }
    static func transition(_ state: State, effect: IOEffect) -> Transition { (state, effect) }
    static func unsafe(_ action: @escaping () -> Void) -> Transition { action(); return (nil, nil) }
}
```

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

func runIOEffect(_ effect: IOEffect) -> EffectSequence {
    switch effect {
    case let .authenticate(username, password):
        return AsyncStream { continuation in
            Task {
                // Pure IO: execute requests and surface outcomes, no branching
                do {
                    let token = try await api.login(username, password)
                    continuation.yield(.loginResponse(.success(token)))
                } catch {
                    continuation.yield(.loginResponse(.failure(.network(error))))
                }

                do {
                    let profile = try await api.fetchProfile()
                    continuation.yield(.profileResponse(.success(profile)))
                } catch {
                    continuation.yield(.profileResponse(.failure(.network(error))))
                }

                continuation.finish()
            }
        }
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
func runIOEffect(_ effect: IOEffect) throws -> EffectSequence  // ❌
```

### 5. Decision Logic in Reducers

```swift
// Wrong: Logic in IO
func runIOEffect(_ effect: IOEffect) -> EffectSequence {
    switch effect {
    case .fetchData(let useCache):
        // if useCache && cache.hasData {  // ❌ Decision in IO
        //     yield .dataFetched(cache.data)
        // }
        return AsyncStream { continuation in
            continuation.finish()
        }
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

func runIOEffect(_ effect: IOEffect) -> EffectSequence {
    switch effect {
    case .fetchData:
        return AsyncStream { continuation in
            Task {
                do {
                    let data = try await api.fetch()
                    continuation.yield(.dataFetched(data))
                } catch {
                    continuation.yield(.fetchFailed(error))
                }
                continuation.finish()
            }
        }
    }
}

// Migrating from single-result to stream:
// Old: async -> IOResult?
// New: return AsyncStream<IOResult> { continuation in
//   if let result = oldReturnValue { continuation.yield(result) }
//   continuation.finish()
// }
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

func runIOEffect(_ effect: IOEffect) -> EffectSequence {
    switch effect {
    case .fetchData:
        return AsyncStream { continuation in
            Task {
                do {
                    let data = try await api.fetch()
                    continuation.yield(.dataFetched(data))
                } catch {
                    continuation.yield(.fetchFailed(error))
                }
                continuation.finish()
            }
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
