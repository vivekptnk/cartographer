# Cartographer

**An offline-first collaborative map annotation engine for Apple platforms.**

Cartographer lets users annotate maps (pins, routes, polygons, notes) that work completely offline and sync conflict-free across devices using CRDTs when connectivity returns.

Built for field researchers, hikers, geologists, and anyone who needs maps without cell service.

## Architecture

```
┌─────────────────────────────────────────┐
│              SwiftUI Views              │
├─────────────────────────────────────────┤
│         MapCoordinator (@MainActor)     │
├──────────┬──────────┬───────────────────┤
│ TileEngine│Annotation│   SyncEngine     │
│          │ Engine   │                   │
├──────────┴──────────┴───────────────────┤
│         CRDT Operation Log              │
│    (HLC + LWW-Register + OR-Set)        │
├─────────────────────────────────────────┤
│     SQLite (WAL mode) + R-Tree          │
└─────────────────────────────────────────┘
```

## Key Technical Decisions

| Component | Choice | Why |
|-----------|--------|-----|
| Storage | Raw SQLite3 C API | Zero dependencies, WAL mode, BLOB perf |
| Spatial Index | Custom R-tree | In-memory Swift structs, native kNN, bulk load |
| Conflict Resolution | CRDTs | No central server, mathematically convergent |
| Sync | CloudKit | Zero infrastructure, free tier, built-in auth |

See `docs/adr/` for full rationale on each decision.

## What Makes This Different

**CRDT Sync Engine** — Every annotation edit is recorded as an operation in a log. Operations use Hybrid Logical Clocks for causal ordering. Fields resolve via Last-Writer-Wins registers. Annotation collections use Observed-Remove Sets with add-wins semantics. Two devices can edit the same annotation offline for weeks — when they sync, the result is deterministic and conflict-free.

**Harness-Driven Development** — Test harnesses define the complete behavioral contract for every component before implementation begins. The harnesses are the spec. See `docs/adr/ADR-005-harness-driven.md`.

**Custom R-Tree** — A pure Swift spatial index with quadratic split, range queries, nearest-neighbor search, and Sort-Tile-Recursive bulk loading. Handles 10K+ annotations with sub-10ms range queries.

## Build & Test

```bash
swift build                                    # Build library
swift test                                     # All tests
swift test --filter CRDTHarnessTests           # CRDT correctness harness
swift test --filter TileHarnessTests           # Tile engine harness
swift test --filter RTreeHarnessTests          # Spatial index harness
swift test --filter SyncHarnessTests           # Sync convergence harness
swift test --filter BenchmarkTests             # Performance benchmarks
```

## Performance Targets

| Operation | Target |
|-----------|--------|
| Tile cache read | < 5ms |
| R-tree range query (10K annotations) | < 10ms |
| CRDT merge (1K operations) | < 50ms |
| HLC timestamp generation | < 1μs |
| Map pan with 5K annotations | < 16ms frame time |

## Project Structure

```
Sources/Cartographer/
├── Core/           # Types, protocols, errors — no dependencies
├── CRDT/           # HLC, LWW-Register, OR-Set, Operation, OperationLog
├── Spatial/        # R-tree, BoundingBox queries
├── TileEngine/     # Cache, MKTileOverlay, region downloader
├── Annotations/    # Annotation engine, rendering, clustering
├── Sync/           # CloudKit transport, sync state machine
└── Export/         # GeoJSON, KML, PDF exporters

Tests/CartographerTests/
├── Harness/        # Source-of-truth behavioral contracts (DO NOT MODIFY)
├── Benchmarks/     # Performance regression tests
└── */              # Additional unit tests per module
```

## Contributing

This repo is designed for AI-assisted development. Clone it, open Claude Code, and run:

```
/onboard
```

Then pick a story from `docs/PRD.md` and implement it:

```
/story CG-005
```

See `CONTRIBUTING.md` for full guidelines.

## Requirements

- Swift 6.0+
- iOS 17+ / macOS 14+
- Xcode 16+
- Zero external dependencies

## License

MIT — see `LICENSE`.
