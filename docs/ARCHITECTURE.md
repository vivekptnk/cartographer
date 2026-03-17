# Cartographer Architecture

## System Overview

Cartographer is a layered system where every mutation flows through a CRDT operation log before reaching storage. This ensures that all changes are replayable, mergeable, and conflict-free.

```
┌───────────────────────────────────────────────────┐
│                   SwiftUI Layer                    │
│  MapView, AnnotationSheet, ProjectList, SyncBadge │
└──────────────────────┬────────────────────────────┘
                       │ @MainActor
┌──────────────────────▼────────────────────────────┐
│               MapCoordinator                       │
│  Owns MKMapView delegate, overlay management,      │
│  annotation clustering, gesture handling            │
└───┬──────────────┬────────────────┬───────────────┘
    │              │                │
┌───▼────┐  ┌─────▼──────┐  ┌─────▼──────┐
│  Tile  │  │ Annotation │  │   Sync     │
│ Engine │  │  Engine     │  │  Engine    │
└───┬────┘  └─────┬──────┘  └─────┬──────┘
    │              │                │
    │         ┌────▼────┐    ┌─────▼──────┐
    │         │  R-Tree │    │  CloudKit  │
    │         │  Index  │    │  Transport │
    │         └────┬────┘    └─────┬──────┘
    │              │                │
┌───▼──────────────▼────────────────▼───────────────┐
│              CRDT Operation Log                    │
│  HybridLogicalClock, LWWRegister, ORSet            │
│  Every mutation → Operation → append to log         │
└──────────────────────┬────────────────────────────┘
                       │
┌──────────────────────▼────────────────────────────┐
│             DatabaseActor (SQLite)                  │
│  WAL mode, prepared statements, migrations          │
│  Tables: tiles, annotations, operations, projects   │
└───────────────────────────────────────────────────┘
```

## Data Flow

### Write Path (User adds annotation)
1. User taps map → `MapCoordinator` receives gesture
2. `MapCoordinator` calls `AnnotationEngine.create(type:coordinate:)`
3. `AnnotationEngine` generates `HLC` timestamp
4. Creates `Operation(type: .insert, entity: .annotation, hlc: hlc, payload: ...)`
5. Appends operation to `CRDTOperationLog` via `DatabaseActor`
6. Materializes current state from operation log → `Annotation` struct
7. Inserts into `RTree` for spatial queries
8. Returns to `MapCoordinator` → updates MKMapView

### Read Path (Map viewport changes)
1. `MKMapView` calls `mapViewDidChangeVisibleRegion`
2. `MapCoordinator` computes bounding box from visible region
3. Queries `RTree.search(boundingBox:)` → returns annotation IDs
4. Fetches full `Annotation` structs from `DatabaseActor`
5. Diff against currently displayed annotations → add/remove from map

### Sync Path (Device comes online)
1. `SyncEngine` detects connectivity via `NWPathMonitor`
2. Queries `DatabaseActor` for operations with `synced = false`
3. Serializes operations → `CKRecord` batch
4. Pushes to CloudKit zone
5. Pulls remote operations since last sync token
6. For each remote operation: append to local log, re-materialize state
7. CRDT guarantees: same operations in any order → same final state

### Tile Path (Map needs tiles)
1. `MKTileOverlay.loadTile(at:result:)` called by MapKit
2. Check `TileCache` (SQLite) for `(x, y, z)` key
3. Cache hit → return `Data` immediately (target: < 5ms)
4. Cache miss online → fetch from tile server, store in cache, return
5. Cache miss offline → return placeholder tile (grey with grid)
6. Background: `RegionDownloader` pre-fetches tiles for offline regions

## Key Design Decisions

See `docs/adr/` for full rationale. Summary:

| Decision | Choice | Why |
|----------|--------|-----|
| Database | Raw SQLite3 C API | Zero overhead, WAL mode, full control |
| Spatial Index | Custom R-tree in Swift | MapKit's built-in clustering is insufficient for 10K+ pins |
| Conflict Resolution | CRDTs (HLC + LWW + OR-Set) | No central server needed, works offline |
| Sync Transport | CloudKit | Free with iCloud, handles auth, built into Apple ecosystem |
| Tile Format | Standard slippy map (z/x/y) | Compatible with OSM, Mapbox, custom tile servers |

## Module Dependency Graph
```
Core ← (no dependencies, pure types + protocols)
  ↑
CRDT ← Core (HLC, LWW, ORSet, OperationLog)
  ↑
Spatial ← Core (RTree, BoundingBox)
  ↑
TileEngine ← Core (TileCache, TileOverlay, RegionDownloader)
  ↑
Annotations ← Core, CRDT, Spatial (AnnotationEngine, AnnotationStore)
  ↑
Sync ← Core, CRDT (SyncEngine, CloudKitTransport)
  ↑
Export ← Core, Annotations (GeoJSON, KML, PDF exporters)
```

## Extension Points

### Custom Tile Sources
Conform to `TileSource` protocol:
```swift
protocol TileSource: Sendable {
    func tileURL(for coordinate: TileCoordinate) -> URL
    var attribution: String { get }
}
```

### Custom Annotation Types
Add cases to `AnnotationType` enum, implement rendering in `AnnotationRenderer`.

### Alternative Sync Backends
Conform to `SyncTransport` protocol to replace CloudKit:
```swift
protocol SyncTransport: Sendable {
    func push(operations: [Operation]) async throws
    func pull(since token: SyncToken?) async throws -> ([Operation], SyncToken)
}
```

## Threading Model

| Component | Isolation | Why |
|-----------|-----------|-----|
| MapCoordinator | `@MainActor` | MKMapView is main-thread only |
| DatabaseActor | `actor` | Serializes all SQLite access |
| TileCache | `actor` | Serializes cache reads/writes |
| SyncEngine | `actor` | Serializes sync state machine |
| RTree | Value type (struct) | Copied per query, no shared mutable state |
| HLC | `actor` | Monotonic clock requires serialization |
| All data models | `Sendable struct` | Safe to pass across isolation boundaries |
