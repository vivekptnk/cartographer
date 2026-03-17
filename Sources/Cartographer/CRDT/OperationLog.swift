// MARK: - Operation Log
// Append-only log of all mutations. The foundation of the CRDT sync engine.
// State is materialized by replaying operations.

import Foundation

/// Append-only operation log backed by SQLite.
/// All state in Cartographer derives from replaying this log.
public actor OperationLog {

    public init() {}

    /// Append an operation to the log.
    /// Target: < 2ms.
    public func append(_ operation: Operation) async throws {
        // TODO: Implement for CG-010
        // 1. Insert into SQLite `operations` table
        // 2. Set synced = false
        fatalError("Not yet implemented — implement for CG-010")
    }

    /// Materialize the current state of an entity by replaying all its operations.
    /// Operations are applied in HLC order. LWW-Register semantics for fields.
    public func materialize(entityID: EntityID) async throws -> Annotation? {
        // TODO: Implement for CG-010
        // 1. SELECT * FROM operations WHERE entity_id = ? ORDER BY hlc_physical, hlc_logical
        // 2. Apply each operation in order:
        //    - .insert → create base Annotation
        //    - .update → apply field changes via LWW
        //    - .delete → return nil
        // 3. Return final state
        fatalError("Not yet implemented — implement for CG-010")
    }

    /// Materialize all annotations for a project.
    public func materializeProject(projectID: EntityID) async throws -> [Annotation] {
        // TODO: Implement for CG-010
        // 1. Get all unique entity IDs for the project
        // 2. Materialize each
        // 3. Filter out deleted (nil) results
        fatalError("Not yet implemented — implement for CG-010")
    }

    /// Get all unsynced operations for push.
    public func unsynced() async throws -> [Operation] {
        // TODO: Implement for CG-010
        // SELECT * FROM operations WHERE synced = 0 ORDER BY hlc_physical, hlc_logical
        fatalError("Not yet implemented — implement for CG-010")
    }

    /// Mark operations as synced after successful push.
    public func markSynced(operationIDs: [EntityID]) async throws {
        // TODO: Implement for CG-010
        // UPDATE operations SET synced = 1 WHERE id IN (...)
        fatalError("Not yet implemented — implement for CG-010")
    }

    /// Apply remote operations (from sync pull). Idempotent — duplicate IDs are ignored.
    public func applyRemote(_ operations: [Operation]) async throws {
        // TODO: Implement for CG-010
        // INSERT OR IGNORE INTO operations ... (duplicate IDs are no-ops)
        fatalError("Not yet implemented — implement for CG-010")
    }
}
