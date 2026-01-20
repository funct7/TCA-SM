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
    typealias IOResultStream = AsyncStream<IOResult>

    typealias Transition = (State?, IOEffect?)

    static func reduceInput(_ state: State, _ input: Input) -> Transition
    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition
    func runIOEffect(_ ioEffect: IOEffect) -> IOResultStream
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

## Macros

### @StateMachine Macro

The `@StateMachine` macro generates the Action typealias automatically:

```swift
@StateMachine
struct MyFeature: StateMachine {
    struct State { ... }
    enum Input { ... }
    enum IOResult { ... }
    // No need for: typealias Action = StateMachineEvent<Input, IOResult>
}
```

**Generated code**:
```swift
typealias Action = StateMachineEvent<Input, IOResult>
```

### ComposableEffect Macro (Internal)

Add the `@ComposableEffect` attribute to any effect enum to synthesize scoped helpers that lift enum cases into `ComposableEffect` values. This keeps reducer code terse even when mixing nested combinators:

```swift
@ComposableEffect
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

### EffectComposition Macro

`@EffectComposition` enables composing multiple effects with `.merge` (parallel) and `.concat` (sequential) combinators. Applied to the feature type (struct/actor), it provides:

- **Effect composition**: Enables `.merge` (run effects in parallel) and `.concat` (run effects sequentially)
- Auto-applies `@ComposableEffect` to the nested `IOEffect` enum
- Synthesizes reducer plumbing (`reduce`, `applyIOEffect`, `apply`, `body`) that extracts and executes composed effects
- Generates a `runIOEffect(_:) -> IOResultStream` dispatcher plus a private `EffectRunner` protocol with per-case methods
- **Auto-detects `@ComposableStateMachine`**: When both macros are present, it automatically includes `nestedBody` in the generated `body`

To use, apply `@EffectComposition` to your feature and conform to the synthesized `{Feature}.EffectRunner` by implementing one method per `IOEffect` case. In your reducers, you can then compose effects using `.merge` and `.concat`:

**Minimal example**

```swift
@StateMachine
@EffectComposition
struct Feature: StateMachine {
    struct State: Equatable { var count = 0 }
    enum Input { case tap }

    // @ComposableEffect is auto-applied by @EffectComposition
    enum IOEffect {
        case fetch(Int)
        case log(Int)
    }

    typealias IOResult = TaskResult<String>

    static func reduceInput(_ state: State, _ input: Input) -> Transition {
        // Composition stays ergonomic in reducers.
        run(.concat(
            .merge(.log(state.count), .log(state.count * 2)),
            .fetch(state.count)
        ))
    }

    static func reduceIOResult(_ state: State, _ result: IOResult) -> Transition {
        nextState(state) // handle result normally
    }
}

// The macro synthesizes Feature.EffectRunner; implement one method per IOEffect case.
extension Feature: Feature.EffectRunner {
    func runFetch(_ value: Int) -> IOResultStream {
        IOResultStream { continuation in
            let task = Task {
                do {
                    let (data, _) = try await URLSession.shared
                        .data(from: URL(string: "https://numbersapi.com/\(value)/trivia")!)
                    continuation.yield(.success(String(decoding: data, as: UTF8.self)))
                } catch {
                    continuation.yield(.failure(error))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func runLog(_ value: Int) -> IOResultStream {
        IOResultStream { continuation in
            continuation.yield(.success("log: \(value)"))
            continuation.finish()
        }
    }
}
```

**Before vs After (manual vs composable)**

```swift
// BEFORE: manual plumbing, no composition helpers
@ComposableEffect
enum IOEffect { case fetch(Int), log(Int) }

struct Feature: StateMachine {
    // ... State, Input, IOResult, Action

    static func reduceInput(_ state: State, _ input: Input) -> Transition {
        // Must return plain IOEffect (no merge/concat helpers)
        run(.fetch(state.count))
    }

    func runIOEffect(_ effect: IOEffect) async -> IOResult? {
        switch effect {
        case .fetch(let value): /* fetch + map to IOResult */
        case .log(let value): /* log */; return nil
        }
    }
}

// AFTER: composable, macro-generated reducer + dispatcher
@EffectComposition
struct Feature: StateMachine {
    // ... State, Input, IOResult, Action
    @ComposableEffect enum IOEffect { case fetch(Int), log(Int) }

    static func reduceInput(_ state: State, _ input: Input) -> Transition {
        // Can compose freely
        run(.concat(.log(state.count), .fetch(state.count)))
    }
}

extension Feature: Feature.EffectRunner {
    func runFetch(_ value: Int) -> IOResultStream { /* fetch */ }
    func runLog(_ value: Int) -> IOResultStream { /* log */ }
}
```

**Prompt: non-composable → composable**

Copy/paste and fill in effect/result names when asking your AI assistant:

> Convert this StateMachine to use `@EffectComposition`.
> - Apply `@EffectComposition` to the feature type.
> - Ensure `IOEffect` is annotated `@ComposableEffect` (the macro will add it if missing).
> - Move each `runIOEffect` branch into the corresponding `{Feature}.EffectRunner` method `run<Case>` and return `IOResultStream`.
> - Keep reducer composition using `.merge/.concat` helpers (now available on `IOEffect`).

**Prompt: composable → non-composable**

> Convert this StateMachine back to manual (non-composable) wiring.
> - Remove `@EffectComposition` and `EffectRunner` conformance.
> - Reintroduce a single `runIOEffect(_:)` that switches over `IOEffect` and returns `IOResult?` or `IOResultStream`.
> - Replace composed calls with plain `IOEffect` cases or manually flatten `.merge/.concat` usage.

## State Machine Composition

### ComposableStateMachine Macro

The `@ComposableStateMachine` macro enables clean, flat composition of child state machines without nested action cases. It generates `NestedStateMachine` reducers that automatically forward parent `Input`/`IOResult` cases to children while preserving effect propagation.

**Key Benefits**:
- Flat `Input` enums - no `.counter(.input(.incrementTapped))` nesting
- Automatic effect propagation from child to parent
- Type-safe forwarding with `@Forward` markers
- Clean view code: `store.send(.input(.counterIncrement))`

**Basic Usage**:

```swift
@StateMachine
@ComposableStateMachine
@EffectComposition
struct ParentFeature: StateMachine {
    @ObservableState
    struct State: Equatable {
        var parentData: String?
        @NestedState var counter = CounterFeature.State()
        @NestedState var presets = PresetsFeature.State()
    }

    enum Input: Sendable {
        case parentButtonTapped

        @Forward(CounterFeature.Input.incrementTapped)
        case counterIncrement

        @Forward(CounterFeature.Input.decrementTapped)
        case counterDecrement

        @Forward(PresetsFeature.Input.loadButtonTapped)
        case presetsLoad

        // Associated values are automatically forwarded
        @Forward(PresetsFeature.Input.saveButtonTapped)
        case presetsSave(count: Int, fact: String)
    }

    enum IOEffect: Sendable {
        case fetchData
    }

    enum IOResult: Sendable {
        case dataResult(TaskResult<String>)

        // Whole enum forwarding - receives all child IOResults
        @Forward(PresetsFeature.IOResult.self)
        case presetsResult(PresetsFeature.IOResult)
    }

    static func reduceInput(_ state: State, _ input: Input) -> Transition {
        switch input {
        case .parentButtonTapped:
            run(.fetchData)
        case .counterIncrement, .counterDecrement:
            identity  // Automatically forwarded to CounterFeature
        case .presetsLoad, .presetsSave:
            identity  // Automatically forwarded to PresetsFeature
        }
    }

    static func reduceIOResult(_ state: State, _ ioResult: IOResult) -> Transition {
        switch ioResult {
        case .dataResult(.success(let data)):
            nextState(withVar(state, \.parentData, data))
        case .dataResult(.failure):
            identity
        case .presetsResult:
            identity  // Automatically forwarded to PresetsFeature
        }
    }
}

extension ParentFeature: ParentFeature.EffectRunner {
    func runFetchData() -> IOResultStream {
        .single { .dataResult(.success("data")) }
    }
}
```

**View Usage** - Clean, flat API:

```swift
struct ParentView: View {
    let store: StoreOf<ParentFeature>

    var body: some View {
        Form {
            // No nested action cases!
            Button("Increment") { store.send(.input(.counterIncrement)) }
            Button("Decrement") { store.send(.input(.counterDecrement)) }
            Button("Load Presets") { store.send(.input(.presetsLoad)) }
            Button("Save") {
                store.send(.input(.presetsSave(count: store.counter.count, fact: "test")))
            }
        }
    }
}
```

### Markers

**@NestedState** - Marks State properties containing child feature state:

```swift
struct State {
    @NestedState var counter: CounterFeature.State
    @NestedState var presets: PresetsFeature.State
}
```

Type inference works with initializers:
```swift
@NestedState var counter = CounterFeature.State()  // ✅ Inferred
@NestedState var counter: CounterFeature.State    // ✅ Explicit
```

**@Forward** - Marks Input/IOResult cases that forward to children:

```swift
enum Input {
    // No associated values
    @Forward(CounterFeature.Input.incrementTapped)
    case counterIncrement

    // With associated values - labels are preserved
    @Forward(PresetsFeature.Input.saveButtonTapped)
    case presetsSave(count: Int, fact: String)
}

enum IOResult {
    // Whole enum forwarding - receives all child IOResults
    @Forward(PresetsFeature.IOResult.self)
    case presetsResult(PresetsFeature.IOResult)
}
```

### Generated Code

The macro generates:
1. **nestedBody** - `NestedStateMachine` reducers for each child feature
2. **Effect mapping** - Child effects are automatically mapped to parent IOResults

```swift
// Generated by @ComposableStateMachine
@ReducerBuilder<State, Action>
var nestedBody: some Reducer<State, Action> {
    NestedStateMachine<State, Action, CounterFeature>(
        state: \.counter,
        toChildAction: { (action: Action) -> CounterFeature.Action? in
            guard case .input(let input) = action else { return nil }
            switch input {
            case .counterIncrement: return .input(.incrementTapped)
            case .counterDecrement: return .input(.decrementTapped)
            default: return nil
            }
        },
        fromChildAction: { @Sendable (childAction: CounterFeature.Action) -> Action? in
            nil  // CounterFeature has no IOResults
        },
        child: { CounterFeature() }
    )

    NestedStateMachine<State, Action, PresetsFeature>(
        state: \.presets,
        toChildAction: { (action: Action) -> PresetsFeature.Action? in
            switch action {
            case .input(let input):
                switch input {
                case .presetsLoad: return .input(.loadButtonTapped)
                case .presetsSave(let count, let fact):
                    return .input(.saveButtonTapped(count: count, fact: fact))
                default: return nil
                }
            case .ioResult(let ioResult):
                switch ioResult {
                case .presetsResult(let childResult): return .ioResult(childResult)
                default: return nil
                }
            }
        },
        fromChildAction: { @Sendable (childAction: PresetsFeature.Action) -> Action? in
            switch childAction {
            case .ioResult(let result): return .ioResult(.presetsResult(result))
            default: return nil
            }
        },
        child: { PresetsFeature() }
    )
}
```

### NestedStateMachine Reducer

`NestedStateMachine` is the runtime component that enables composition without TCA's `Scope` + CasePaths pattern:

```swift
public struct NestedStateMachine<ParentState, ParentAction, Child: Reducer>: Reducer {
    private let statePath: WritableKeyPath<ParentState, Child.State>
    private let toChildAction: (ParentAction) -> Child.Action?
    private let fromChildAction: @Sendable (Child.Action) -> ParentAction?
    private let child: () -> Child

    public func reduce(into state: inout ParentState, action: ParentAction) -> Effect<ParentAction> {
        guard let childAction = toChildAction(action) else {
            return .none
        }
        // Run child reducer and map effects back to parent
        let childEffect = child().reduce(into: &state[keyPath: statePath], action: childAction)
        return childEffect.map { fromChildAction($0)! }
    }
}
```

**Key Properties**:
- **Bidirectional mapping**: `toChildAction` forwards parent actions to child, `fromChildAction` maps child effects back
- **Effect propagation**: Child effects (IOResults) are automatically propagated to parent
- **No case paths needed**: Uses plain switch statements instead of TCA's reflection-based routing

### Macro Orthogonality

The macros are independent and composable:

| Macro | Purpose | Can Use Alone |
|-------|---------|---------------|
| `@StateMachine` | Generates Action typealias | ✅ Yes |
| `@ComposableStateMachine` | State machine composition (nesting children) | ✅ Yes |
| `@EffectComposition` | Effect composition (`.merge`, `.concat`) | ✅ Yes |

**Use all three** when you need:
- Nested child features AND
- Effect composition (`.merge/.concat`)

```swift
@StateMachine                // Generates Action typealias
@ComposableStateMachine      // Generates nestedBody
@EffectComposition      // Generates body (auto-includes nestedBody)
struct Feature: StateMachine {
    // ... nested children with @NestedState
    // ... effects with .merge/.concat
}
```

**Use only @StateMachine + @ComposableStateMachine** when:
- You have nested children
- No effect composition needed

```swift
@StateMachine
@ComposableStateMachine
struct Feature: StateMachine {
    typealias IOEffect = Never  // No parent effects
    // ... nested children forward to parent
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
