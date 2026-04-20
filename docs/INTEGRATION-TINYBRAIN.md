# Cartographer ↔ TinyBrain Integration Contract

This document defines the hand-off between the Cartographer engine and a
TinyBrain-backed implementation of `SmartAnnotationService`. It is the
source of truth that both sides — Cartographer (engine consumer) and
TinyBrain (inference provider) — agree to implement against.

The only cross-product code shape Cartographer commits to is the
protocol itself. Everything else in this document is a contract on
runtime behavior: lifecycle, threading, input shaping, fallback, and
resource budget.

## 1. The seam

Declared in `Sources/Cartographer/Annotations/SmartAnnotationService.swift`:

```swift
public protocol SmartAnnotationService: Sendable {
    func search(query: String, in corpus: [Annotation]) async throws -> [EntityID]
    func summarize(annotations: [Annotation]) async throws -> String
}
```

- `Sendable` is required. Cartographer calls into this protocol from
  actor-isolated contexts; any non-`Sendable` implementation breaks
  Swift 6 strict concurrency.
- The protocol lives in the engine. Cartographer ships a
  `MockSmartAnnotationService` alongside it (keyword-hit search, typed
  count summary) so every call site in the demo app and the library has
  a working, offline, zero-dependency default.
- Only the `Any SmartAnnotationService` existential (or a concrete
  generic parameter) crosses module boundaries. Cartographer never
  imports TinyBrain types directly.

TinyBrain ships an adapter module (e.g. `TinyBrainCartographerBridge`)
that conforms a concrete type — the recommended name is
`TinyBrainSmartService` — to `SmartAnnotationService`. The demo app
(and downstream hosts) receive the bridge as a dependency at wire-up
time; swapping implementations is a one-line change at the composition
root.

## 2. Model lifecycle and `.tbf` load path

### 2.1 Load path

Cartographer does **not** bundle model weights. The host app is
responsible for placing the `.tbf` file on disk before constructing the
TinyBrain service. Supported sources, in order of preference:

1. **App bundle resource** — bundled with the demo or host app during
   CI, resolved via `Bundle.main.url(forResource:withExtension:)`.
2. **Application Support / Caches** — downloaded on first launch, or
   copied out of the bundle to allow hot-swapping. Path is owned by the
   host app, not by Cartographer.
3. **Shared App Group container** — for hosts that share a model across
   an app + extension.

The TinyBrain adapter accepts a `URL` in its initializer:

```swift
public init(modelURL: URL) throws
```

Cartographer and the demo app resolve the URL and hand it to the
adapter. The adapter is the only component that knows what a `.tbf`
file contains.

### 2.2 Lifecycle

- **Initialization is cheap.** The adapter's initializer validates the
  URL exists, the file is readable, and the header magic matches. It
  does **not** load weights. Heavy work is deferred.
- **First call loads the model.** The first `search` or `summarize`
  call triggers weight loading (mmapped where possible, INT4 quantized
  per [CHA-108](/CHA/issues/CHA-108)). Expected cold-start budget on
  an A17 Pro: ≤ 800 ms for a ~700 MB INT4 TinyLlama-class model. On
  older hardware (A14), budget is ≤ 1.5 s.
- **Warm calls are steady-state.** After first load, the adapter keeps
  the model resident for the process lifetime. It must not eagerly
  unload between calls.
- **Memory pressure eviction.** The adapter subscribes to memory
  pressure signals (`DispatchSource` memory-pressure events on iOS).
  On `critical` pressure, the adapter unloads the model and subsequent
  calls throw `SmartAnnotationServiceError.modelUnavailable`, causing
  Cartographer to fall through to the mock (see §5).
- **Explicit shutdown is not part of the protocol.** Hosts that need
  deterministic teardown for testing construct a fresh adapter per
  test.

## 3. Threading contract

Cartographer's UI is `@MainActor`. The `SmartAnnotationService` methods
are `async` and must **never** block the calling thread — all model
inference runs off the main actor.

Recommended implementation shape:

```swift
public actor TinyBrainSmartService: SmartAnnotationService {
    private let modelURL: URL
    private var session: TinyBrainSession?   // lazy-loaded on first use

    public init(modelURL: URL) throws { ... }

    public func search(query: String, in corpus: [Annotation]) async throws -> [EntityID] {
        let session = try ensureSession()
        return try await session.rankByRelevance(query: query, corpus: corpus)
    }
}
```

Requirements TinyBrain must satisfy:

- The conformance is an `actor` (or an isolated reference type) so
  concurrent calls from multiple actors serialize safely inside the
  adapter. A shared mutable `TinyBrainSession` is otherwise unsafe.
- Inference itself runs on a dedicated background queue owned by the
  adapter. It must not hop to `MainActor` during inference.
- Long-running calls are **cancellable**. If the Swift `Task` is
  cancelled (e.g. the user dismisses the search sheet), the adapter
  must stop producing tokens and return promptly. Throw
  `CancellationError` on cancel — Cartographer treats this as
  non-exceptional.
- The adapter must honor `Task` priority. Search from a user-visible
  UI action runs at `.userInitiated`; background route summarization
  runs at `.utility`.

## 4. Input shaping

### 4.1 Token budget per call

TinyBrain's baseline target is TinyLlama-class: a **2,048-token**
context window. Per-call budgets Cartographer commits to:

| Call        | Prompt budget       | Response budget  |
|-------------|---------------------|------------------|
| `search`    | ≤ 1,536 input tokens | ≤ 256 output tokens (we only need IDs, not prose) |
| `summarize` | ≤ 1,536 input tokens | ≤ 384 output tokens |

"Tokens" here is the adapter's tokenizer count, not characters. The
adapter exposes an approximate counter:

```swift
func estimatedTokenCount(_ text: String) -> Int
```

Cartographer uses this during chunking (§4.2). If the adapter is not
yet available at chunking time, Cartographer assumes **4 chars ≈ 1
token** as a pessimistic heuristic.

### 4.2 Chunking a large annotation corpus

Annotation corpora can exceed the context window — a single project
may carry thousands of pins, notes, and route descriptions. Chunking
lives on the Cartographer side:

- **`search`** — we build a per-annotation string of
  `"<title>\n<body>\n<metadata-values>"`. We greedily pack annotations
  into chunks that fit the per-call prompt budget, making one
  `search` call per chunk, then merge results by taking each
  annotation's **maximum relevance rank across chunks**. Final result
  is sorted by that max rank. Expected chunk size: 20–50 annotations
  depending on body length.
- **`summarize`** — we first ask the adapter to summarize each chunk,
  then ask it to summarize the concatenation of those summaries
  ("reduce" step). For the v0.2 mock, summarization is a single call
  regardless of corpus size; TinyBrain's adapter is expected to do
  the map/reduce internally when called with a large corpus **or**
  accept a pre-chunked call pattern. Cartographer commits to the
  pre-chunked pattern as the default.
- **Hard ceiling.** If a single annotation's serialized form exceeds
  the prompt budget (e.g. a 30 KB route description), Cartographer
  truncates the `body` field to fit and tags the truncation in a
  log line. It does not throw.

### 4.3 Determinism

Cartographer does not assume deterministic outputs from TinyBrain.
Tests at the Cartographer boundary mock the service; TinyBrain owns
its own perplexity/regression harness (tracked on
[CHA-108](/CHA/issues/CHA-108)).

## 5. Fallback when TinyBrain is unavailable

TinyBrain can be unavailable for several reasons: the `.tbf` file is
missing, the device is under memory pressure, the adapter threw
`modelUnavailable`, or the host app intentionally shipped without a
model. Cartographer must degrade gracefully.

Rule (in the composition root, not inside the engine):

```swift
// Pseudo-code for the demo app's AppContainer.
let smart: any SmartAnnotationService = {
    if let tinyBrain = try? TinyBrainSmartService(modelURL: modelURL) {
        return FallbackSmartAnnotationService(
            primary: tinyBrain,
            secondary: MockSmartAnnotationService(),
            onFallback: { signal in unavailableSignal.send(signal) }
        )
    }
    return MockSmartAnnotationService()
}()
```

Contract for the fallback wrapper (Cartographer-side, future work):

- Catches `SmartAnnotationServiceError.modelUnavailable` and
  `SmartAnnotationServiceError.inferenceFailed` thrown from the
  primary, then re-invokes the secondary. `invalidQuery` is **not**
  caught — it is a programmer error on the caller side.
- Emits a `SmartServiceUnavailable` signal (typed event, not an
  `Error`) that the UI can subscribe to. Typical UI response: show a
  small banner reading "Smart search is offline — using keyword
  match." Never block the user flow.
- Does not attempt to re-probe the primary on every call. A
  back-off (first retry after 60 s, doubling to a 10-min ceiling) is
  applied. The adapter's `modelUnavailable` is treated as sticky.
- The wrapper is `Sendable` and has no I/O of its own.

The fallback wrapper is follow-up work; it is **not** required to ship
CHA-138. For v0.2 the demo app constructs the `MockSmartAnnotationService`
directly when no model is configured.

## 6. Footprint budget

Cartographer's tile cache is the largest on-disk consumer today. Any
TinyBrain model must coexist with it on devices that have as little as
64 GB of storage.

| Resource           | Budget           | Source of budget |
|--------------------|------------------|------------------|
| Model file (`.tbf`)| ≤ 1.0 GB disk    | Half the default tile-cache ceiling of 2 GB. |
| Resident memory    | ≤ 400 MB working set | iOS background-inference heuristic; leaves headroom for MapKit + R-tree. |
| Cold-start CPU     | ≤ 1.5 s on A14   | User-perceivable interaction latency. |
| Per-call latency   | ≤ 400 ms (`search` on 50-annotation chunk) | Map tap interaction feels local. |

If a larger model is required, TinyBrain and Cartographer must
co-sign a revision of this document before integration ships. The
tile-cache quota in `TileCache` is configurable; raising one budget
requires lowering another.

## 7. Versioning

This document is versioned alongside the Cartographer engine. Breaking
changes to the `SmartAnnotationService` protocol require:

- A new major version of the Cartographer Swift package.
- A corresponding TinyBrain adapter release.
- An ADR under `docs/adr/` explaining the motivation.

Non-breaking changes (adding new optional methods with default
implementations, loosening return-type requirements) are handled as
minor releases.

## 8. Checklist for the TinyBrain side

- [ ] Ship a `TinyBrainSmartService` actor conforming to
      `SmartAnnotationService` (imported from the Cartographer package).
- [ ] Support `.tbf` loading from an injected `URL`; do not bundle
      weights in the adapter.
- [ ] Honor per-call token budgets in §4.1 or throw
      `SmartAnnotationServiceError.invalidQuery` with the overflow.
- [ ] Surface `SmartAnnotationServiceError.modelUnavailable` on memory
      pressure or failed load. Stay usable (mock fallback) after the
      throw.
- [ ] Cancellable inference (respond to `Task.cancel()` within one
      token-generation iteration).
- [ ] Perplexity regression harness (tracked on
      [CHA-108](/CHA/issues/CHA-108)).
- [ ] Cross-team hand-off ticket acknowledged by the TinyBrain team;
      real implementation filed separately with
      `blockedByIssueIds = [CHA-108]`.

## 9. Related

- Protocol source: `Sources/Cartographer/Annotations/SmartAnnotationService.swift`
- Mock: `MockSmartAnnotationService` in the same file
- Unit tests: `Tests/CartographerTests/SmartAnnotationServiceTests.swift`
- Parent plan: [CHA-123](/CHA/issues/CHA-123#document-plan)
- Int4 quantization regression harness: [CHA-108](/CHA/issues/CHA-108)
- Architecture overview: `docs/ARCHITECTURE.md`
