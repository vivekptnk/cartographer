// MARK: - Tile Cache
// SQLite-backed tile cache with LRU eviction.
// All access serialized through actor isolation.

import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

// MARK: - Sendable SQLite Handle Wrapper

/// Wraps raw SQLite pointers so they can be stored in an actor and cleaned up in deinit.
/// Safety: all actual usage is serialized through the enclosing actor.
private final class SQLiteHandle: Sendable {
    nonisolated(unsafe) let db: OpaquePointer?
    nonisolated(unsafe) let getStmt: OpaquePointer?
    nonisolated(unsafe) let putStmt: OpaquePointer?
    nonisolated(unsafe) let updateAccessStmt: OpaquePointer?
    nonisolated(unsafe) let sizeStmt: OpaquePointer?
    nonisolated(unsafe) let countStmt: OpaquePointer?
    nonisolated(unsafe) let lastUpdatedStmt: OpaquePointer?

    init(
        db: OpaquePointer?,
        getStmt: OpaquePointer?,
        putStmt: OpaquePointer?,
        updateAccessStmt: OpaquePointer?,
        sizeStmt: OpaquePointer?,
        countStmt: OpaquePointer?,
        lastUpdatedStmt: OpaquePointer?
    ) {
        self.db = db
        self.getStmt = getStmt
        self.putStmt = putStmt
        self.updateAccessStmt = updateAccessStmt
        self.sizeStmt = sizeStmt
        self.countStmt = countStmt
        self.lastUpdatedStmt = lastUpdatedStmt
    }

    deinit {
        sqlite3_finalize(getStmt)
        sqlite3_finalize(putStmt)
        sqlite3_finalize(updateAccessStmt)
        sqlite3_finalize(sizeStmt)
        sqlite3_finalize(countStmt)
        sqlite3_finalize(lastUpdatedStmt)
        sqlite3_close(db)
    }
}

// MARK: - TileCache Actor

/// Cache for map tiles backed by SQLite BLOB storage.
public actor TileCache {
    /// Maximum cache size in bytes. Default 500MB.
    public let maxCacheSize: Int

    /// In-memory LRU tracking for fast eviction decisions.
    private var accessOrder: [TileCoordinate] = []

    /// Sendable handle wrapping all SQLite pointers.
    private let handle: SQLiteHandle

    public init(maxCacheSize: Int = 500 * 1024 * 1024, path: String? = nil) {
        self.maxCacheSize = maxCacheSize
        let dbPath = path ?? ":memory:"

        // Open database
        var dbHandle: OpaquePointer?
        guard sqlite3_open(dbPath, &dbHandle) == SQLITE_OK else {
            self.handle = SQLiteHandle(db: nil, getStmt: nil, putStmt: nil, updateAccessStmt: nil, sizeStmt: nil, countStmt: nil, lastUpdatedStmt: nil)
            return
        }

        // WAL mode for better concurrent read performance
        sqlite3_exec(dbHandle, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(dbHandle, "PRAGMA synchronous=NORMAL", nil, nil, nil)

        // Create table
        let createSQL = """
            CREATE TABLE IF NOT EXISTS tiles (
                z INTEGER NOT NULL,
                x INTEGER NOT NULL,
                y INTEGER NOT NULL,
                data BLOB NOT NULL,
                last_accessed INTEGER NOT NULL,
                PRIMARY KEY (z, x, y)
            )
            """
        sqlite3_exec(dbHandle, createSQL, nil, nil, nil)

        let indexSQL = "CREATE INDEX IF NOT EXISTS idx_tiles_lru ON tiles (last_accessed ASC)"
        sqlite3_exec(dbHandle, indexSQL, nil, nil, nil)

        // Prepare statements
        var gStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, "SELECT data FROM tiles WHERE z = ? AND x = ? AND y = ?", -1, &gStmt, nil)

        var pStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, "INSERT OR REPLACE INTO tiles (z, x, y, data, last_accessed) VALUES (?, ?, ?, ?, ?)", -1, &pStmt, nil)

        var uStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, "UPDATE tiles SET last_accessed = ? WHERE z = ? AND x = ? AND y = ?", -1, &uStmt, nil)

        var szStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, "SELECT COALESCE(SUM(length(data)), 0) FROM tiles", -1, &szStmt, nil)

        var cStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, "SELECT COUNT(*) FROM tiles", -1, &cStmt, nil)

        var luStmt: OpaquePointer?
        sqlite3_prepare_v2(dbHandle, "SELECT MAX(last_accessed) FROM tiles", -1, &luStmt, nil)

        self.handle = SQLiteHandle(
            db: dbHandle,
            getStmt: gStmt,
            putStmt: pStmt,
            updateAccessStmt: uStmt,
            sizeStmt: szStmt,
            countStmt: cStmt,
            lastUpdatedStmt: luStmt
        )

        // Load existing access order
        var order: [TileCoordinate] = []
        var loadStmt: OpaquePointer?
        if sqlite3_prepare_v2(dbHandle, "SELECT z, x, y FROM tiles ORDER BY last_accessed ASC", -1, &loadStmt, nil) == SQLITE_OK {
            while sqlite3_step(loadStmt) == SQLITE_ROW {
                let z = Int(sqlite3_column_int(loadStmt, 0))
                let x = Int(sqlite3_column_int(loadStmt, 1))
                let y = Int(sqlite3_column_int(loadStmt, 2))
                order.append(TileCoordinate(z: z, x: x, y: y))
            }
            sqlite3_finalize(loadStmt)
        }
        self.accessOrder = order
    }

    // MARK: - Public API

    /// Retrieve a tile from the cache. Returns nil on cache miss.
    /// Target: < 5ms.
    public func get(_ coordinate: TileCoordinate) async -> Data? {
        guard let stmt = handle.getStmt else { return nil }

        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(coordinate.z))
        sqlite3_bind_int(stmt, 2, Int32(coordinate.x))
        sqlite3_bind_int(stmt, 3, Int32(coordinate.y))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        guard let blobPointer = sqlite3_column_blob(stmt, 0) else { return nil }
        let blobSize = Int(sqlite3_column_bytes(stmt, 0))
        let data = Data(bytes: blobPointer, count: blobSize)

        // Update LRU tracking
        touchAccessOrder(coordinate)
        updateLastAccessed(coordinate)

        return data
    }

    /// Store a tile in the cache. Triggers eviction if over capacity.
    /// Target: < 10ms.
    public func put(_ coordinate: TileCoordinate, data: Data) async {
        guard let stmt = handle.putStmt else { return }

        let now = currentTimestamp()

        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(coordinate.z))
        sqlite3_bind_int(stmt, 2, Int32(coordinate.x))
        sqlite3_bind_int(stmt, 3, Int32(coordinate.y))
        _ = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, 4, rawBuffer.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        sqlite3_bind_int64(stmt, 5, Int64(now))

        sqlite3_step(stmt)

        // Update in-memory LRU
        touchAccessOrder(coordinate)

        // Evict if needed
        await evictIfNeeded()
    }

    /// Evict oldest tiles when cache exceeds maxCacheSize.
    /// Removes oldest 20% by last_accessed timestamp.
    public func evictIfNeeded() async {
        let size = await currentSize()
        guard size > maxCacheSize else { return }

        let total = await tileCount()
        guard total > 0 else { return }

        let evictCount = max(1, total / 5) // 20%

        let sql = "DELETE FROM tiles WHERE rowid IN (SELECT rowid FROM tiles ORDER BY last_accessed ASC LIMIT ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(evictCount))
        sqlite3_step(stmt)

        // Rebuild in-memory access order
        reloadAccessOrder()
    }

    /// Current cache size in bytes.
    public func currentSize() async -> Int {
        guard let stmt = handle.sizeStmt else { return 0 }

        sqlite3_reset(stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Number of cached tiles.
    public func tileCount() async -> Int {
        guard let stmt = handle.countStmt else { return 0 }

        sqlite3_reset(stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Total bytes occupied by cached tile payloads. Int64-typed public
    /// metadata accessor for UI consumers (e.g. offline-indicator popover).
    /// Thin wrapper over `currentSize()`.
    public func totalSize() async -> Int64 {
        Int64(await currentSize())
    }

    /// Timestamp of the most recently accessed tile, or nil when the cache
    /// is empty. Derived from `MAX(last_accessed)` on the tiles table.
    public func lastUpdated() async -> Date? {
        guard let stmt = handle.lastUpdatedStmt else { return nil }

        sqlite3_reset(stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        // Empty table → MAX(...) returns NULL.
        guard sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }

        let ms = sqlite3_column_int64(stmt, 0)
        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    // MARK: - Private Helpers

    private func touchAccessOrder(_ coordinate: TileCoordinate) {
        accessOrder.removeAll { $0 == coordinate }
        accessOrder.append(coordinate)
    }

    private func updateLastAccessed(_ coordinate: TileCoordinate) {
        guard let stmt = handle.updateAccessStmt else { return }

        sqlite3_reset(stmt)
        sqlite3_bind_int64(stmt, 1, Int64(currentTimestamp()))
        sqlite3_bind_int(stmt, 2, Int32(coordinate.z))
        sqlite3_bind_int(stmt, 3, Int32(coordinate.x))
        sqlite3_bind_int(stmt, 4, Int32(coordinate.y))
        sqlite3_step(stmt)
    }

    private func reloadAccessOrder() {
        accessOrder.removeAll()

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.db, "SELECT z, x, y FROM tiles ORDER BY last_accessed ASC", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let z = Int(sqlite3_column_int(stmt, 0))
            let x = Int(sqlite3_column_int(stmt, 1))
            let y = Int(sqlite3_column_int(stmt, 2))
            accessOrder.append(TileCoordinate(z: z, x: x, y: y))
        }
    }

    private func currentTimestamp() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}
