# ADR-002: Custom R-Tree Over SQLite R*Tree Extension

## Status
Accepted

## Context
We need spatial indexing for 10K+ annotations with range queries and nearest-neighbor lookups.

## Decision
Implement a custom R-tree in pure Swift rather than using SQLite's R*Tree extension or Core Location's built-in facilities.

## Rationale
- **In-memory performance.** Our R-tree lives in memory (rebuilt from SQLite on launch). In-memory Swift structs with value semantics are faster than crossing the SQLite FFI boundary for every query.
- **Nearest-neighbor.** SQLite's R*Tree doesn't natively support kNN — you'd need a workaround with expanding bounding boxes. Our implementation has native kNN.
- **Bulk loading.** Sort-Tile-Recursive (STR) bulk loading from a sorted array is significantly faster than N individual inserts for initial load.
- **Testability.** A pure Swift value type is trivially testable without database setup.
- **Portfolio signal.** Implementing an R-tree from scratch demonstrates deep knowledge of spatial data structures — directly relevant for Apple Maps work.

## Consequences
- Must implement quadratic split, insert, delete, search, kNN ourselves
- R-tree state must be synced with SQLite on mutations (dual write)
- More code to maintain than using a built-in extension

## Alternatives Rejected
- **SQLite R*Tree extension:** Cross-FFI overhead for every spatial query, no native kNN.
- **Core Location region monitoring:** Limited to 20 monitored regions, wrong abstraction.
- **Quadtree:** Worse worst-case performance for non-uniform distributions (clustered annotations).
