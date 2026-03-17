# ADR-001: Raw SQLite C API Over Core Data / GRDB

## Status
Accepted

## Context
We need persistent storage for tiles (BLOBs up to 256KB), annotations, and CRDT operations. Options: Core Data, GRDB, raw SQLite3 C API.

## Decision
Use the SQLite3 C API directly via Swift's `CSQLite` module bridge.

## Rationale
- **Zero dependencies.** Core Data pulls in a massive framework. GRDB is excellent but adds an external dependency.
- **WAL mode control.** We need WAL journal mode for concurrent reads during sync. Core Data abstracts this away.
- **BLOB performance.** Direct `sqlite3_blob_open` for tile data avoids Core Data's overhead of wrapping BLOBs in NSData.
- **Prepared statements.** We have ~15 known queries. Preparing them once and rebinding is faster than any ORM.
- **Transparent migrations.** A simple version table + SQL migration scripts is easier to reason about than Core Data model versions.
- **CRDT operation log.** We need append-only semantics with custom ordering — Core Data's object graph model fights this pattern.

## Consequences
- More boilerplate for query building and result parsing
- Must handle memory management for C API objects manually
- No free Xcode data model editor
- Must write our own migration runner

## Alternatives Rejected
- **Core Data:** Too much abstraction over SQLite for our use case. Object graph model is wrong fit for append-only operation log.
- **GRDB:** Excellent library, but adds external dependency. We want zero-dep.
- **SwiftData:** Too new, limited control over WAL mode and BLOB handling.
