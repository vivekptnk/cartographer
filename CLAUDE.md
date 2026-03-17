# Cartographer

## Overview
Cartographer is a **zero-dependency, offline-first collaborative map annotation engine** for Apple platforms. It combines MapKit tile caching, CRDT-based conflict resolution, R-tree spatial indexing, and CloudKit sync into a single Swift Package — designed for field researchers, hikers, and anyone who needs maps that work without connectivity.

**Read the full PRD before starting any work:** `docs/PRD.md`
**Read architecture before any structural change:** `docs/ARCHITECTURE.md`
**Read ADRs before refactoring anything:** `docs/adr/`

## Tech Stack
- **Language:** Swift 6.0+ (strict concurrency, complete sendability checking)
- **Platforms:** iOS 17+, macOS 14+
- **Frameworks:** MapKit, SQLite3 (C API directly, no wrappers), CloudKit, CoreLocation, CoreGraphics
- **Dependencies:** ZERO external dependencies. Apple frameworks + system SQLite only.

## Code Standards

### Concurrency
- All database access through a dedicated `DatabaseActor`
- All MapKit overlay work on `@MainActor`
- Never block the main thread for I/O — all tile loads and sync are async
- Use `sending` parameter annotation for cross-isolation transfers

### Types
- Value types (`struct`) for all data models: `Annotation`, `TileCoordinate`, `Operation`
- Reference types (`class`) only for: actors, MapKit overlays/renderers, long-lived coordinators
- Every public type conforms to `Sendable`

### Error Handling
- Domain-specific error enums: `TileError`, `CRDTError`, `SyncError`
- Never force unwrap outside test files
- All SQLite calls wrapped in result-checking helpers

### Naming
- CRDT types prefixed: `CRDTRegister`, `CRDTORSet`, `CRDTOperationLog`
- Tile types prefixed: `Tile`, `TileCache`, `TileOverlay`
- Spatial types prefixed: `RTree`, `RTreeNode`, `BoundingBox`
- Test harnesses suffixed: `*Harness` (e.g., `CRDTHarness`, `TileHarness`)

### SQL
- All queries use prepared statements with parameterized bindings
- WAL journal mode enabled at connection open
- Migrations tracked with a version table
- Every table has `created_at` and `updated_at` timestamps

## Architecture (Quick Reference)
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
├─────────────────────────────────────────┤
│     SQLite (DatabaseActor)  + R-Tree    │
└─────────────────────────────────────────┘
```

## Build & Test
```bash
swift build                                    # Build library
swift test                                     # All tests
swift test --filter CRDTHarnessTests           # CRDT correctness harness
swift test --filter TileHarnessTests           # Tile engine harness  
swift test --filter RTreeHarnessTests          # Spatial index harness
swift test --filter SyncHarnessTests           # Sync convergence harness
swift test --filter Benchmark                  # Performance benchmarks
```

## Performance Targets
| Operation | Target | Measured |
|-----------|--------|----------|
| Tile cache read (SQLite) | < 5ms | — |
| Tile cache write | < 10ms | — |
| R-tree range query (10K annotations) | < 10ms | — |
| R-tree insert | < 1ms | — |
| CRDT merge (1K operations) | < 50ms | — |
| HLC timestamp generation | < 1μs | — |
| Operation log append | < 2ms | — |
| Full sync cycle (100 ops) | < 500ms | — |

## Git Workflow
- **main** — protected, requires passing harness + CI
- **develop** — integration branch
- Feature branches: `feat/CG-XXX-description`
- Every PR must: pass all harnesses, include benchmark deltas, have no force unwraps

## Harness-Driven Development
This repo uses harness-driven development. The test harnesses define the contract:

1. **Read the harness** for the component you're implementing
2. **Make the harness compile** by creating types/protocols with stub implementations
3. **Make the harness pass** by filling in real implementations
4. **Run benchmarks** to verify performance targets

The harnesses are the source of truth. If a harness test fails, the implementation is wrong — never modify a harness to make it pass.
