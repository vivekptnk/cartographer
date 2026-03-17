# SQLite Patterns for Cartographer

## Connection Setup

```swift
actor DatabaseActor {
    private var db: OpaquePointer?

    func open(path: String) throws {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw DatabaseError.connectionFailed(String(cString: sqlite3_errmsg(db)))
        }
        // WAL mode for concurrent reads
        try execute("PRAGMA journal_mode = WAL")
        // Foreign keys
        try execute("PRAGMA foreign_keys = ON")
    }
}
```

## Prepared Statements

```swift
// Prepare once, bind many times
private var insertTileStmt: OpaquePointer?

func prepareStatements() throws {
    let sql = "INSERT OR REPLACE INTO tiles (z, x, y, data, last_accessed) VALUES (?, ?, ?, ?, ?)"
    guard sqlite3_prepare_v2(db, sql, -1, &insertTileStmt, nil) == SQLITE_OK else {
        throw DatabaseError.prepareStatementFailed(String(cString: sqlite3_errmsg(db)))
    }
}

func insertTile(_ coord: TileCoordinate, data: Data) throws {
    sqlite3_reset(insertTileStmt)
    sqlite3_bind_int(insertTileStmt, 1, Int32(coord.z))
    sqlite3_bind_int(insertTileStmt, 2, Int32(coord.x))
    sqlite3_bind_int(insertTileStmt, 3, Int32(coord.y))
    data.withUnsafeBytes { ptr in
        sqlite3_bind_blob(insertTileStmt, 4, ptr.baseAddress, Int32(data.count), nil)
    }
    sqlite3_bind_double(insertTileStmt, 5, Date().timeIntervalSince1970)
    guard sqlite3_step(insertTileStmt) == SQLITE_DONE else {
        throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
    }
}
```

## Migration System

```swift
private let migrations: [(version: Int, sql: String)] = [
    (1, """
        CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
        INSERT OR IGNORE INTO schema_version VALUES (0);

        CREATE TABLE IF NOT EXISTS tiles (
            z INTEGER NOT NULL,
            x INTEGER NOT NULL,
            y INTEGER NOT NULL,
            data BLOB NOT NULL,
            last_accessed REAL NOT NULL,
            PRIMARY KEY (z, x, y)
        );

        CREATE TABLE IF NOT EXISTS annotations (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            type TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS operations (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            project_id TEXT NOT NULL,
            hlc_physical INTEGER NOT NULL,
            hlc_logical INTEGER NOT NULL,
            hlc_node TEXT NOT NULL,
            payload BLOB NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        CREATE INDEX idx_ops_entity ON operations(entity_id);
        CREATE INDEX idx_ops_project ON operations(project_id);
        CREATE INDEX idx_ops_synced ON operations(synced);

        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sync_state (
            project_id TEXT PRIMARY KEY,
            change_token BLOB,
            last_sync REAL
        );
    """),
]

func runMigrations() throws {
    let currentVersion = try getCurrentVersion()
    for migration in migrations where migration.version > currentVersion {
        try execute(migration.sql)
        try setVersion(migration.version)
    }
}
```

## LRU Eviction

```swift
func evictIfNeeded(maxBytes: Int) throws {
    let currentSize = try getCacheSize()
    guard currentSize > maxBytes else { return }

    // Delete oldest 20%
    let deleteCount = try getTileCount() / 5
    try execute("""
        DELETE FROM tiles WHERE rowid IN (
            SELECT rowid FROM tiles ORDER BY last_accessed ASC LIMIT \(deleteCount)
        )
    """)
}
```

## Transaction Pattern

```swift
func inTransaction<T>(_ body: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE")
    do {
        let result = try body()
        try execute("COMMIT")
        return result
    } catch {
        try? execute("ROLLBACK")
        throw error
    }
}
```
