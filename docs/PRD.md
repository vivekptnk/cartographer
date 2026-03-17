# Cartographer — Product Requirements Document

## Vision
An offline-first collaborative map annotation engine that works without connectivity, syncs conflict-free when online, and handles 10K+ annotations at 60fps.

## Target Users
Field researchers, hikers, military planners, geologists — anyone who annotates maps in areas with unreliable connectivity.

---

## Epic 1: Tile Engine & Cache

### CG-001: SQLite Database Foundation
**Points:** 3 | **Priority:** P0 | **Depends on:** Nothing

Set up the SQLite database layer with WAL mode, migrations, and the `DatabaseActor`.

**Tasks:**
- Create `DatabaseActor` with `sqlite3` C API wrapper
- Implement connection pooling with WAL journal mode
- Create migration system with version tracking table
- Define schema: `tiles`, `annotations`, `operations`, `projects`, `sync_state`
- Write prepared statement helpers with parameterized bindings

**Acceptance Criteria:**
- [ ] WAL mode verified active after connection open
- [ ] Migrations run idempotently (running twice = no error)
- [ ] All queries use parameterized bindings (grep for string interpolation = 0 hits)
- [ ] DatabaseActor harness passes

**Learn:** SQLite WAL mode, prepared statements, actor isolation for database access

---

### CG-002: Tile Cache with LRU Eviction
**Points:** 5 | **Priority:** P0 | **Depends on:** CG-001

Implement a tile cache backed by SQLite that stores tile image data keyed by `(z, x, y)` with LRU eviction.

**Tasks:**
- Create `TileCoordinate` value type (z, x, y, tileSource)
- Implement `TileCache` actor with get/put/evict
- LRU tracking via `last_accessed` timestamp column
- Configurable max cache size (default 500MB)
- Eviction runs when cache exceeds threshold, removes oldest 20%

**Acceptance Criteria:**
- [ ] Cache read < 5ms for cached tile (benchmark)
- [ ] Cache write < 10ms (benchmark)
- [ ] LRU eviction triggers at threshold and removes correct tiles
- [ ] TileHarness passes all cache scenarios

**Learn:** Slippy map tile coordinates (z/x/y), LRU eviction strategies, BLOB storage in SQLite

---

### CG-003: Custom MKTileOverlay & Region Downloader
**Points:** 5 | **Priority:** P0 | **Depends on:** CG-002

Subclass `MKTileOverlay` to serve tiles from cache, with a background region downloader for offline use.

**Tasks:**
- Subclass `MKTileOverlay`, override `loadTile(at:result:)`
- Cache-first strategy: check SQLite → fetch remote → store → return
- Offline fallback: return placeholder tile (grey grid) on cache miss
- `RegionDownloader`: given a bounding box and zoom range, download all tiles
- Progress tracking via AsyncStream
- Download survives app backgrounding (URLSession background config)

**Acceptance Criteria:**
- [ ] Cached tiles render without network (airplane mode test)
- [ ] Placeholder tiles render for uncached regions offline
- [ ] Region download reports accurate progress
- [ ] Download resumes after app restart

**Learn:** MKTileOverlay subclassing, URLSession background downloads, tile coordinate math

---

## Epic 2: Annotation Engine & R-Tree

### CG-004: Annotation Data Model
**Points:** 2 | **Priority:** P0 | **Depends on:** CG-001

Define the core annotation types and their data model.

**Tasks:**
- Create `Annotation` struct: id (UUID), type, coordinate, title, body, metadata, timestamps
- Create `AnnotationType` enum: `.pin`, `.route`, `.polygon`, `.note`
- Route = ordered array of coordinates; Polygon = closed coordinate ring
- All types conform to `Sendable`, `Codable`, `Identifiable`
- JSON serialization for operation payloads

**Acceptance Criteria:**
- [ ] All annotation types round-trip through Codable
- [ ] Sendable conformance compiles under strict concurrency
- [ ] Coordinate precision: 7 decimal places (±11mm accuracy)

**Learn:** CLLocationCoordinate2D precision, Codable for complex enums

---

### CG-005: R-Tree Spatial Index
**Points:** 8 | **Priority:** P0 | **Depends on:** CG-004

Implement an R-tree in pure Swift for fast spatial queries over annotations.

**Tasks:**
- Create `BoundingBox` struct (minLat, maxLat, minLon, maxLon)
- Implement `RTree<Element>` with insert, delete, search (range query)
- Node splitting strategy: quadratic split
- Configurable max entries per node (default: 16)
- Nearest-neighbor query for tap-to-select
- Bulk loading via Sort-Tile-Recursive (STR) for initial load

**Acceptance Criteria:**
- [ ] Range query < 10ms for 10K annotations (benchmark)
- [ ] Insert < 1ms (benchmark)
- [ ] Nearest-neighbor returns correct result for all edge cases
- [ ] RTreeHarness passes: insert, delete, range, nearest, bulk load
- [ ] Tree stays balanced after 10K random insertions

**Learn:** R-tree data structure, quadratic split algorithm, STR bulk loading, spatial query algorithms

---

### CG-006: Annotation Rendering & Clustering
**Points:** 5 | **Priority:** P1 | **Depends on:** CG-005

Custom MapKit annotation views with clustering at low zoom levels.

**Tasks:**
- Custom `MKAnnotationView` subclasses for each annotation type
- Pin: colored circle with icon; Route: polyline overlay; Polygon: filled overlay
- Clustering: when zoom < threshold, group nearby annotations
- Cluster view shows count badge
- Selection: tap annotation → show detail sheet

**Acceptance Criteria:**
- [ ] All 4 annotation types render correctly on map
- [ ] Clustering activates at zoom level < 12
- [ ] < 16ms frame time during pan with 5K annotations visible
- [ ] Tap selects correct annotation (nearest-neighbor via R-tree)

**Learn:** MKAnnotationView, MKOverlayRenderer, annotation clustering, MapKit coordinate systems

---

## Epic 3: CRDT Sync Engine

### CG-007: Hybrid Logical Clock
**Points:** 3 | **Priority:** P0 | **Depends on:** Nothing

Implement a Hybrid Logical Clock (HLC) for causal ordering of operations.

**Tasks:**
- Create `HLC` struct: (physicalTime: UInt64, logicalCounter: UInt16, nodeID: UUID)
- `HLC` actor for thread-safe clock management
- `tick()` → new HLC guaranteed greater than previous
- `merge(remote:)` → new HLC ≥ max(local, remote)
- Compact binary encoding for storage (16 bytes)

**Acceptance Criteria:**
- [ ] Monotonically increasing: 1000 sequential ticks, each > previous
- [ ] Merge correctness: merge with future clock → advances; merge with past → no regression
- [ ] Timestamp generation < 1μs (benchmark)
- [ ] Binary encoding round-trips perfectly
- [ ] CRDTHarness HLC tests pass

**Learn:** Hybrid Logical Clocks (Kulkarni et al.), Lamport timestamps, causal ordering

---

### CG-008: Last-Writer-Wins Register
**Points:** 3 | **Priority:** P0 | **Depends on:** CG-007

Implement LWW-Register for annotation field-level conflict resolution.

**Tasks:**
- Create `LWWRegister<Value: Sendable & Codable>` with (value, hlc) pairs
- `set(value:, hlc:)` → updates only if hlc > current
- `merge(remote:)` → keeps value with higher HLC
- Used for: annotation title, body, coordinate, metadata fields
- Each field independently mergeable

**Acceptance Criteria:**
- [ ] Concurrent edits: higher HLC wins deterministically
- [ ] Merge is commutative: merge(a,b) == merge(b,a)
- [ ] Merge is idempotent: merge(a,a) == a
- [ ] Merge is associative: merge(merge(a,b),c) == merge(a,merge(b,c))
- [ ] CRDTHarness LWW tests pass

**Learn:** LWW-Register CRDT, commutativity/idempotency/associativity proofs

---

### CG-009: Observed-Remove Set
**Points:** 5 | **Priority:** P0 | **Depends on:** CG-007

Implement OR-Set for managing annotation collections within a project.

**Tasks:**
- Create `ORSet<Element: Hashable & Sendable & Codable>`
- Each add tagged with unique HLC
- Remove removes all observed tags for element
- Concurrent add + remove → element exists (add wins over concurrent remove)
- `merge(remote:)` → union of add-tags, remove only tags you've seen

**Acceptance Criteria:**
- [ ] Add-wins semantics verified for all concurrent scenarios
- [ ] Merge commutative, idempotent, associative
- [ ] Handles: add/add, add/remove, remove/remove, concurrent add+remove
- [ ] CRDTHarness ORSet tests pass
- [ ] 1K element set merge < 50ms (benchmark)

**Learn:** OR-Set CRDT (Shapiro et al.), causal consistency, tombstone management

---

### CG-010: Operation Log & State Materialization
**Points:** 5 | **Priority:** P0 | **Depends on:** CG-008, CG-009

Build the operation log that records every mutation and materializes current state.

**Tasks:**
- Create `Operation` struct: id, type (.insert/.update/.delete), entity, hlc, payload (JSON)
- `OperationLog` backed by SQLite `operations` table
- `append(operation:)` → insert with `synced = false`
- `materialize(entityID:)` → replay all operations for entity → current state
- `materialize(project:)` → replay all operations → full project state
- Snapshot optimization: periodically snapshot materialized state to avoid full replay

**Acceptance Criteria:**
- [ ] Operations are idempotent: applying same operation twice = same state
- [ ] Replay in any order produces identical final state (fuzz test)
- [ ] Append < 2ms (benchmark)
- [ ] Full materialization of 1K ops < 50ms (benchmark)
- [ ] CRDTHarness operation log tests pass

**Learn:** Event sourcing, operation-based CRDTs, snapshot optimization

---

### CG-011: CloudKit Sync Transport
**Points:** 8 | **Priority:** P1 | **Depends on:** CG-010

Sync operations between devices via CloudKit.

**Tasks:**
- Create private CloudKit zone for each project
- `SyncEngine` actor: manages push/pull state machine
- Push: batch unsynced operations → CKRecord array → save to zone
- Pull: fetch changes since last server change token
- Conflict: impossible at operation level (CRDTs are conflict-free)
- Retry with exponential backoff on transient errors
- `NWPathMonitor` to detect connectivity changes

**Acceptance Criteria:**
- [ ] Two simulators sync correctly after offline edits on both
- [ ] Sync survives app termination mid-push (resumes on next launch)
- [ ] No data loss under any network failure scenario
- [ ] SyncHarness convergence tests pass
- [ ] Full sync cycle (100 ops) < 500ms excluding network

**Learn:** CloudKit zones, CKServerChangeToken, NWPathMonitor, exponential backoff

---

## Epic 4: Export & Polish

### CG-012: Export (GeoJSON, KML, PDF)
**Points:** 5 | **Priority:** P2 | **Depends on:** CG-006

Export annotations in standard formats.

**Tasks:**
- GeoJSON exporter: annotations → FeatureCollection
- KML exporter: annotations → KML document with styles
- PDF exporter: MKMapSnapshotter → render annotations → Core Graphics PDF
- Include title, legend, scale bar, coordinate grid in PDF

**Acceptance Criteria:**
- [ ] GeoJSON validates against RFC 7946
- [ ] KML opens correctly in Google Earth
- [ ] PDF includes all visible annotations with correct positions
- [ ] Export of 1K annotations < 2s

**Learn:** GeoJSON RFC 7946, KML specification, MKMapSnapshotter, Core Graphics PDF

---

### CG-013: UI Polish & App Store Readiness
**Points:** 5 | **Priority:** P2 | **Depends on:** CG-012

**Tasks:**
- Onboarding flow: create project, download region, add first annotation
- Empty states for project list and annotation list
- Offline mode indicator in navigation bar
- Haptic feedback on pin drop, annotation selection
- Performance profiling with Instruments
- README with architecture diagram, CRDT explanation, screenshots

**Acceptance Criteria:**
- [ ] < 16ms frame time during map pan with 5K+ annotations
- [ ] All empty states have clear call-to-action
- [ ] README includes build instructions, architecture diagram, demo video link
