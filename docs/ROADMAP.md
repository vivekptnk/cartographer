# Cartographer — Roadmap

**Last updated:** 2026-04-23
**Current version:** v0.2.0

This roadmap covers planned engineering milestones for Cartographer. Priorities follow the project's design hierarchy: **offline reliability > sync correctness > performance > feature breadth**.

---

## v0.3.0 — Sync Hardening

**Theme:** Make CRDT sync production-grade across adversarial conditions.

- **Partial-sync resumption** — Support interrupted sync sessions that can resume mid-batch without re-sending all operations.
- **Conflict surfacing UI** — When two devices produce divergent edits that both use add-wins semantics, surface the merged result in a lightweight review sheet instead of silently accepting.
- **HLC drift detection** — Alert when the local Hybrid Logical Clock drifts beyond a configurable threshold from remote nodes; cap drift at 1 second per ADR-003.
- **OR-Set tombstone compaction** — Prune deleted-operation tombstones that are older than the oldest known sync token; prevents unbounded log growth.
- **Sync telemetry** — Structured logging for push/pull byte counts, operation counts, round-trip latency, and convergence lag.

---

## v0.4.0 — R-Tree Spatial Index Milestones

**Theme:** Push the spatial engine to handle 100K+ annotations with no perceptible latency.

- **Bulk-load optimisation** — Extend Sort-Tile-Recursive bulk loading to stream from the SQLite operation log directly, bypassing a full materialise-then-index cycle on cold start.
- **Persistent R-tree** — Serialise the in-memory R-tree to SQLite so the index survives app restarts without a full rebuild.
- **kNN with max-distance bound** — Add an optional `maxDistance` parameter to nearest-neighbor queries so callers can skip the post-filter step.
- **Range-query benchmarks at 100K nodes** — Validate that range queries remain <10 ms at 100K entries; publish results in `docs/benchmarks/`.
- **Dynamic node splitting strategy** — Evaluate Quadratic vs. R* splitting on real-world annotation distributions; ADR if strategy changes.

---

## v0.5.0 — Offline-First Edge Cases

**Theme:** Harden the offline path against edge cases discovered in field use.

- **Tile eviction policy** — Implement LRU eviction in TileCache with a configurable max-disk-usage limit; currently the cache is unbounded.
- **Background tile pre-fetch** — Pre-fetch tiles for the visible region in the background when the device is on Wi-Fi; pause on cellular.
- **Offline annotation queue** — Buffer annotation edits in a separate write-ahead queue when the operation log database is locked or unavailable; flush on availability.
- **Sync-after-reconnect trigger** — Automatically trigger a sync cycle within 5 seconds of network reachability restoration.
- **Corrupt database recovery** — Detect WAL corruption at open time and fall back to a clean database, replaying any unsynced operations from the CloudKit change token.

---

## v0.6.0 — Collaboration Features

**Theme:** Enable real-time-adjacent multi-user annotation on shared projects.

- **Shared projects via CloudKit zones** — Map each Cartographer project to a CloudKit shared zone; allow project owners to invite collaborators via the system share sheet.
- **Presence indicators** — Lightweight presence layer showing which collaborators have the same map region visible; implemented without a central server using CloudKit push.
- **Per-field authorship** — Expose the HLC node ID in the LWW-Register so the UI can attribute the last edit of each annotation field to a specific collaborator.
- **Undo stack with CRDT replay** — Build a bounded undo stack by replaying operation log entries in reverse; integrates with standard SwiftUI undo infrastructure.

---

## v1.0.0 — Platform Expansion

**Theme:** Bring the full Cartographer experience to macOS and iPadOS.

- **macOS Catalyst port** — Deliver a Mac Catalyst build of CartographerDemo that exercises the same engine components; adjust the toolbar and sidebar layout for the desktop idiom.
- **iPadOS split-view** — Run the map view and the annotation editor side-by-side in a UISplitViewController shell; leverage the larger canvas for R-tree visualisation mode.
- **Apple Watch companion** — Send the nearest 3 pins to an Apple Watch complication via WatchConnectivity; read-only, no editing.
- **SwiftUI MapKit integration** — Replace the UIViewRepresentable `DemoMapView` shim with the native SwiftUI `Map` API once it gains sufficient overlay and annotation customisation surface.

---

## Process & Engineering Health

These items are not version-specific but are tracked here for visibility.

- **DocC catalog** — Add a `Documentation.docc` catalog to `Sources/Cartographer/` covering all public types; target 95% doc comment coverage.
- **Execution workspace verification** — Before marking any issue done, verify commits are on `origin` with `git ls-remote`. A commit that is only local is not shipped. Lesson from the ghost-worktree incidents on CHA-135, CHA-136, and CHA-139 where work was reported "done" against SHAs that never reached `origin`.
- **CI harness gate** — Add the CRDT convergence harness and R-tree property tests to a GitHub Actions workflow so regressions are caught before merge.
- **Benchmark regression CI** — Run `swift test --filter BenchmarkTests` in CI and fail the build if any metric regresses by more than 20% from the baseline committed in `docs/benchmarks/`.

---

## Deferred / Deprioritised

| Feature | Reason deferred |
|---------|----------------|
| WebSocket sync transport | CloudKit covers the target use case; WebSocket adds server infrastructure complexity |
| Android / Kotlin port | Out of scope for v1.0; sync protocol is documented for future cross-platform ports |
| AI-powered annotation suggestions | Depends on TinyBrain integration; tracked separately in the cross-product roadmap |
| Vector tile rendering | Performance win is modest vs. implementation cost at current annotation counts |

---

*Issues tracking specific milestones are filed under the Cartographer project in Paperclip. File enhancements against the appropriate milestone issue.*
