// MARK: - Operation Log
// Append-only log of all mutations. The foundation of the CRDT sync engine.
// State is materialized by replaying operations.

import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

// MARK: - Sendable SQLite Handle Wrapper

/// Wraps raw SQLite pointers for the operations table.
/// Safety: all actual usage is serialized through the enclosing actor.
private final class OpLogHandle: Sendable {
    nonisolated(unsafe) let db: OpaquePointer?
    nonisolated(unsafe) let appendStmt: OpaquePointer?
    nonisolated(unsafe) let entityOpsStmt: OpaquePointer?
    nonisolated(unsafe) let projectEntityIDsStmt: OpaquePointer?
    nonisolated(unsafe) let unsyncedStmt: OpaquePointer?
    nonisolated(unsafe) let markSyncedStmt: OpaquePointer?
    nonisolated(unsafe) let insertOrIgnoreStmt: OpaquePointer?

    init(
        db: OpaquePointer?,
        appendStmt: OpaquePointer?,
        entityOpsStmt: OpaquePointer?,
        projectEntityIDsStmt: OpaquePointer?,
        unsyncedStmt: OpaquePointer?,
        markSyncedStmt: OpaquePointer?,
        insertOrIgnoreStmt: OpaquePointer?
    ) {
        self.db = db
        self.appendStmt = appendStmt
        self.entityOpsStmt = entityOpsStmt
        self.projectEntityIDsStmt = projectEntityIDsStmt
        self.unsyncedStmt = unsyncedStmt
        self.markSyncedStmt = markSyncedStmt
        self.insertOrIgnoreStmt = insertOrIgnoreStmt
    }

    deinit {
        sqlite3_finalize(appendStmt)
        sqlite3_finalize(entityOpsStmt)
        sqlite3_finalize(projectEntityIDsStmt)
        sqlite3_finalize(unsyncedStmt)
        sqlite3_finalize(markSyncedStmt)
        sqlite3_finalize(insertOrIgnoreStmt)
        sqlite3_close(db)
    }
}

// MARK: - OperationLog Actor

/// Append-only operation log backed by SQLite.
/// All state in Cartographer derives from replaying this log.
public actor OperationLog {

    private let handle: OpLogHandle

    public init(path: String? = nil) {
        let dbPath = path ?? ":memory:"

        var dbHandle: OpaquePointer?
        guard sqlite3_open(dbPath, &dbHandle) == SQLITE_OK else {
            self.handle = OpLogHandle(
                db: nil, appendStmt: nil, entityOpsStmt: nil,
                projectEntityIDsStmt: nil, unsyncedStmt: nil,
                markSyncedStmt: nil, insertOrIgnoreStmt: nil
            )
            return
        }

        // WAL mode for better concurrent read performance
        sqlite3_exec(dbHandle, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(dbHandle, "PRAGMA synchronous=NORMAL", nil, nil, nil)

        // Create operations table
        let createSQL = """
            CREATE TABLE IF NOT EXISTS operations (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                project_id TEXT NOT NULL,
                hlc_physical INTEGER NOT NULL,
                hlc_logical INTEGER NOT NULL,
                hlc_node_id TEXT NOT NULL,
                payload BLOB NOT NULL,
                synced INTEGER NOT NULL DEFAULT 0
            )
            """
        sqlite3_exec(dbHandle, createSQL, nil, nil, nil)

        // Create indexes for efficient queries
        sqlite3_exec(dbHandle,
            "CREATE INDEX IF NOT EXISTS idx_ops_entity ON operations (entity_id, hlc_physical, hlc_logical)",
            nil, nil, nil)
        sqlite3_exec(dbHandle,
            "CREATE INDEX IF NOT EXISTS idx_ops_project ON operations (project_id)",
            nil, nil, nil)
        sqlite3_exec(dbHandle,
            "CREATE INDEX IF NOT EXISTS idx_ops_synced ON operations (synced)",
            nil, nil, nil)

        // Prepare statements
        var aStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, """
            INSERT INTO operations (id, type, entity_type, entity_id, project_id, hlc_physical, hlc_logical, hlc_node_id, payload, synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, -1, &aStmt, nil)

        var eStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, """
            SELECT id, type, entity_type, entity_id, project_id, hlc_physical, hlc_logical, hlc_node_id, payload, synced
            FROM operations WHERE entity_id = ? ORDER BY hlc_physical ASC, hlc_logical ASC, hlc_node_id ASC
            """, -1, &eStmt, nil)

        var pStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, """
            SELECT DISTINCT entity_id FROM operations WHERE project_id = ?
            """, -1, &pStmt, nil)

        var uStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, """
            SELECT id, type, entity_type, entity_id, project_id, hlc_physical, hlc_logical, hlc_node_id, payload, synced
            FROM operations WHERE synced = 0 ORDER BY hlc_physical ASC, hlc_logical ASC, hlc_node_id ASC
            """, -1, &uStmt, nil)

        // markSynced uses dynamic SQL (variable IN clause), so no prepared stmt here
        let msStmt: OpaquePointer? = nil

        var ioStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, """
            INSERT OR IGNORE INTO operations (id, type, entity_type, entity_id, project_id, hlc_physical, hlc_logical, hlc_node_id, payload, synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, -1, &ioStmt, nil)

        self.handle = OpLogHandle(
            db: dbHandle,
            appendStmt: aStmt,
            entityOpsStmt: eStmt,
            projectEntityIDsStmt: pStmt,
            unsyncedStmt: uStmt,
            markSyncedStmt: msStmt,
            insertOrIgnoreStmt: ioStmt
        )
    }

    // MARK: - Public API

    /// Append an operation to the log.
    /// Target: < 2ms.
    public func append(_ operation: Operation) throws {
        guard let stmt = handle.appendStmt else {
            throw DatabaseError.connectionFailed("OperationLog database not open")
        }

        sqlite3_reset(stmt)
        bindOperation(operation, to: stmt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(handle.db))
            throw DatabaseError.queryFailed("append failed: \(errmsg)")
        }
    }

    /// Materialize the current state of an entity by replaying all its operations.
    /// Operations are applied in HLC order. LWW-Register semantics for fields.
    public func materialize(entityID: EntityID) throws -> Annotation? {
        guard let stmt = handle.entityOpsStmt else {
            throw DatabaseError.connectionFailed("OperationLog database not open")
        }

        sqlite3_reset(stmt)
        let entityStr = entityID.uuidString
        sqlite3_bind_text(stmt, 1, entityStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var annotation: Annotation?
        // LWW registers for each mutable field
        var typeReg: LWWRegister<String>?
        var coordReg: LWWRegister<GeoCoordinate>?
        var titleReg: LWWRegister<String>?
        var bodyReg: LWWRegister<String>?
        var routeReg: LWWRegister<[GeoCoordinate]?>?
        var polygonReg: LWWRegister<[GeoCoordinate]?>?
        var metadataReg: LWWRegister<[String: String]>?
        var isDeleted = false
        var deleteTimestamp: HLCTimestamp?

        while sqlite3_step(stmt) == SQLITE_ROW {
            let op = readOperation(from: stmt)

            switch op.type {
            case .insert:
                // Decode the full annotation payload
                guard let decoded = try? JSONDecoder().decode(Annotation.self, from: op.payload) else {
                    continue
                }
                annotation = decoded
                // Initialize LWW registers from the insert
                typeReg = LWWRegister(value: decoded.type.rawValue, timestamp: op.hlc)
                coordReg = LWWRegister(value: decoded.coordinate, timestamp: op.hlc)
                titleReg = LWWRegister(value: decoded.title, timestamp: op.hlc)
                bodyReg = LWWRegister(value: decoded.body, timestamp: op.hlc)
                routeReg = LWWRegister(value: decoded.routeCoordinates, timestamp: op.hlc)
                polygonReg = LWWRegister(value: decoded.polygonCoordinates, timestamp: op.hlc)
                metadataReg = LWWRegister(value: decoded.metadata, timestamp: op.hlc)
                // If we previously saw a delete with a lower timestamp, it's overridden
                if let dt = deleteTimestamp, dt < op.hlc {
                    isDeleted = false
                    deleteTimestamp = nil
                }

            case .update:
                guard annotation != nil else { continue }
                // Decode field-level updates
                guard let fields = try? JSONDecoder().decode(AnnotationFieldUpdate.self, from: op.payload) else {
                    continue
                }
                if let t = fields.type {
                    if typeReg != nil {
                        typeReg!.set(t, at: op.hlc)
                    } else {
                        typeReg = LWWRegister(value: t, timestamp: op.hlc)
                    }
                }
                if let c = fields.coordinate {
                    if coordReg != nil {
                        coordReg!.set(c, at: op.hlc)
                    } else {
                        coordReg = LWWRegister(value: c, timestamp: op.hlc)
                    }
                }
                if let ti = fields.title {
                    if titleReg != nil {
                        titleReg!.set(ti, at: op.hlc)
                    } else {
                        titleReg = LWWRegister(value: ti, timestamp: op.hlc)
                    }
                }
                if let b = fields.body {
                    if bodyReg != nil {
                        bodyReg!.set(b, at: op.hlc)
                    } else {
                        bodyReg = LWWRegister(value: b, timestamp: op.hlc)
                    }
                }
                if let r = fields.routeCoordinates {
                    if routeReg != nil {
                        routeReg!.set(r, at: op.hlc)
                    } else {
                        routeReg = LWWRegister(value: r, timestamp: op.hlc)
                    }
                }
                if let p = fields.polygonCoordinates {
                    if polygonReg != nil {
                        polygonReg!.set(p, at: op.hlc)
                    } else {
                        polygonReg = LWWRegister(value: p, timestamp: op.hlc)
                    }
                }
                if let m = fields.metadata {
                    if metadataReg != nil {
                        metadataReg!.set(m, at: op.hlc)
                    } else {
                        metadataReg = LWWRegister(value: m, timestamp: op.hlc)
                    }
                }

            case .delete:
                isDeleted = true
                deleteTimestamp = op.hlc
            }
        }

        guard !isDeleted, var result = annotation else { return nil }

        // Apply LWW register values to build final state
        if let t = typeReg, let at = AnnotationType(rawValue: t.value) {
            result.type = at
        }
        if let c = coordReg {
            result.coordinate = c.value
        }
        if let ti = titleReg {
            result.title = ti.value
        }
        if let b = bodyReg {
            result.body = b.value
        }
        if let r = routeReg {
            result.routeCoordinates = r.value
        }
        if let p = polygonReg {
            result.polygonCoordinates = p.value
        }
        if let m = metadataReg {
            result.metadata = m.value
        }

        return result
    }

    /// Materialize all annotations for a project.
    public func materializeProject(projectID: EntityID) throws -> [Annotation] {
        guard let stmt = handle.projectEntityIDsStmt else {
            throw DatabaseError.connectionFailed("OperationLog database not open")
        }

        sqlite3_reset(stmt)
        let projectStr = projectID.uuidString
        sqlite3_bind_text(stmt, 1, projectStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var entityIDs: [EntityID] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let idStr = sqlite3_column_text(stmt, 0) {
                let str = String(cString: idStr)
                if let uuid = UUID(uuidString: str) {
                    entityIDs.append(uuid)
                }
            }
        }

        var results: [Annotation] = []
        for eid in entityIDs {
            if let ann = try materialize(entityID: eid) {
                results.append(ann)
            }
        }
        return results
    }

    /// Get all unsynced operations for push.
    public func unsynced() throws -> [Operation] {
        guard let stmt = handle.unsyncedStmt else {
            throw DatabaseError.connectionFailed("OperationLog database not open")
        }

        sqlite3_reset(stmt)

        var ops: [Operation] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ops.append(readOperation(from: stmt))
        }
        return ops
    }

    /// Mark operations as synced after successful push.
    public func markSynced(operationIDs: [EntityID]) throws {
        guard let db = handle.db else {
            throw DatabaseError.connectionFailed("OperationLog database not open")
        }
        guard !operationIDs.isEmpty else { return }

        // Build dynamic IN clause
        let placeholders = operationIDs.map { _ in "?" }.joined(separator: ",")
        let sql = "UPDATE operations SET synced = 1 WHERE id IN (\(placeholders))"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareStatementFailed("markSynced: \(errmsg)")
        }
        defer { sqlite3_finalize(stmt) }

        for (i, opID) in operationIDs.enumerated() {
            let str = opID.uuidString
            sqlite3_bind_text(stmt, Int32(i + 1), str, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.queryFailed("markSynced failed: \(errmsg)")
        }
    }

    /// Apply remote operations (from sync pull). Idempotent — duplicate IDs are ignored.
    public func applyRemote(_ operations: [Operation]) throws {
        guard let stmt = handle.insertOrIgnoreStmt else {
            throw DatabaseError.connectionFailed("OperationLog database not open")
        }

        for op in operations {
            sqlite3_reset(stmt)
            // Remote operations arrive already synced
            var syncedOp = op
            syncedOp.synced = true
            bindOperation(syncedOp, to: stmt)

            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE else {
                let errmsg = String(cString: sqlite3_errmsg(handle.db))
                throw DatabaseError.queryFailed("applyRemote failed: \(errmsg)")
            }
        }
    }

    // MARK: - Private Helpers

    /// Bind an Operation's fields to a prepared statement (10 parameters).
    private func bindOperation(_ op: Operation, to stmt: OpaquePointer?) {
        let idStr = op.id.uuidString
        let typeStr = op.type.rawValue
        let entityTypeStr = op.entityType.rawValue
        let entityIDStr = op.entityID.uuidString
        let projectIDStr = op.projectID.uuidString
        let nodeIDStr = op.hlc.nodeID.uuidString

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, idStr, -1, transient)
        sqlite3_bind_text(stmt, 2, typeStr, -1, transient)
        sqlite3_bind_text(stmt, 3, entityTypeStr, -1, transient)
        sqlite3_bind_text(stmt, 4, entityIDStr, -1, transient)
        sqlite3_bind_text(stmt, 5, projectIDStr, -1, transient)
        sqlite3_bind_int64(stmt, 6, Int64(op.hlc.physicalTime))
        sqlite3_bind_int(stmt, 7, Int32(op.hlc.logicalCounter))
        sqlite3_bind_text(stmt, 8, nodeIDStr, -1, transient)
        _ = op.payload.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, 9, rawBuffer.baseAddress, Int32(op.payload.count), transient)
        }
        sqlite3_bind_int(stmt, 10, op.synced ? 1 : 0)
    }

    /// Read an Operation from the current row of a statement.
    private func readOperation(from stmt: OpaquePointer?) -> Operation {
        let idStr = String(cString: sqlite3_column_text(stmt, 0))
        let typeStr = String(cString: sqlite3_column_text(stmt, 1))
        let entityTypeStr = String(cString: sqlite3_column_text(stmt, 2))
        let entityIDStr = String(cString: sqlite3_column_text(stmt, 3))
        let projectIDStr = String(cString: sqlite3_column_text(stmt, 4))
        let hlcPhysical = UInt64(sqlite3_column_int64(stmt, 5))
        let hlcLogical = UInt16(sqlite3_column_int(stmt, 6))
        let nodeIDStr = String(cString: sqlite3_column_text(stmt, 7))

        let blobPtr = sqlite3_column_blob(stmt, 8)
        let blobSize = Int(sqlite3_column_bytes(stmt, 8))
        let payload: Data
        if let ptr = blobPtr, blobSize > 0 {
            payload = Data(bytes: ptr, count: blobSize)
        } else {
            payload = Data()
        }

        let synced = sqlite3_column_int(stmt, 9) != 0

        return Operation(
            id: UUID(uuidString: idStr) ?? UUID(),
            type: OperationType(rawValue: typeStr) ?? .insert,
            entityType: EntityType(rawValue: entityTypeStr) ?? .annotation,
            entityID: UUID(uuidString: entityIDStr) ?? UUID(),
            projectID: UUID(uuidString: projectIDStr) ?? UUID(),
            hlc: HLCTimestamp(
                physicalTime: hlcPhysical,
                logicalCounter: hlcLogical,
                nodeID: UUID(uuidString: nodeIDStr) ?? UUID()
            ),
            payload: payload,
            synced: synced
        )
    }
}

// MARK: - Field Update DTO

/// Represents a partial update to an Annotation's fields.
/// Only non-nil fields are applied during materialization.
public struct AnnotationFieldUpdate: Sendable, Codable {
    public var type: String?
    public var coordinate: GeoCoordinate?
    public var title: String?
    public var body: String?
    public var routeCoordinates: [GeoCoordinate]??
    public var polygonCoordinates: [GeoCoordinate]??
    public var metadata: [String: String]?

    public init(
        type: String? = nil,
        coordinate: GeoCoordinate? = nil,
        title: String? = nil,
        body: String? = nil,
        routeCoordinates: [GeoCoordinate]?? = nil,
        polygonCoordinates: [GeoCoordinate]?? = nil,
        metadata: [String: String]? = nil
    ) {
        self.type = type
        self.coordinate = coordinate
        self.title = title
        self.body = body
        self.routeCoordinates = routeCoordinates
        self.polygonCoordinates = polygonCoordinates
        self.metadata = metadata
    }
}
