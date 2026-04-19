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

## CartographerDemo — iOS Reference App

`CartographerDemo/` is the v0.2.0 reference app that exercises every engine component on a real iPhone. Use it to smoke-test an engine change end-to-end before merging to `main`.

**Build from the command line:**

```bash
xcodebuild \
  -project CartographerDemo/CartographerDemo.xcodeproj \
  -scheme CartographerDemo \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build
```

**Run on a real iPhone (iOS 17+):**

1. Open `CartographerDemo/CartographerDemo.xcodeproj` in Xcode 16+.
2. Select your personal or team signing identity under *Signing & Capabilities* (bundle id: `com.garnathdynamics.cartographer.demo`).
3. Pick the attached device as the run destination and hit Run. First launch requests location permission only if you enable user-location in the debug menu; by default the map is static.

**Debug menu** (wrench icon, top-right):

- Seed N synthetic annotations around San Francisco
- Toggle CloudKit sync on/off (uses an in-memory round-trip transport so no iCloud account is required to demo the state machine)
- Switch tile source between OpenStreetMap and OpenTopoMap
- Trigger a region download (zoom 12–14 over the SF bay box)
- Share GeoJSON of the current project via the system share sheet

**Project structure:**

- `CartographerDemo.xcodeproj` — committed, authoritative for `xcodebuild`
- `project.yml` — XcodeGen mirror for diff-friendly structural review. Requires `brew install xcodegen` only if you want to regenerate the `.pbxproj` from scratch; day-to-day builds don't need it.

See [`docs/adr/ADR-006-demo-app-structure.md`](docs/adr/ADR-006-demo-app-structure.md) for the full rationale behind the companion-Xcode-project approach.

**Demo video:** _coming soon_ — placeholder for the v0.2.0 recorded walkthrough. Tracked in CHA-137.

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
├── Annotations/    # Annotation engine, SmartAnnotationService, clustering
├── Sync/           # CloudKit transport, sync state machine
└── Export/         # GeoJSON, KML, PDF exporters

Tests/CartographerTests/
├── Harness/        # Source-of-truth behavioral contracts (DO NOT MODIFY)
├── Benchmarks/     # Performance regression tests
└── */              # Additional unit tests per module

CartographerDemo/
├── CartographerDemo/            # SwiftUI iOS app sources
├── CartographerDemo.xcodeproj/  # Checked in; authoritative for xcodebuild
└── project.yml                  # XcodeGen mirror; diff-friendly spec
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
