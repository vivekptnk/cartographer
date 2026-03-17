// MARK: - Tile Cache
// SQLite-backed tile cache with LRU eviction.
// All access serialized through actor isolation.

import Foundation

/// Cache for map tiles backed by SQLite BLOB storage.
public actor TileCache {
    /// Maximum cache size in bytes. Default 500MB.
    public let maxCacheSize: Int

    /// In-memory LRU tracking for fast eviction decisions.
    private var accessOrder: [TileCoordinate] = []

    public init(maxCacheSize: Int = 500 * 1024 * 1024) {
        self.maxCacheSize = maxCacheSize
    }

    /// Retrieve a tile from the cache. Returns nil on cache miss.
    /// Target: < 5ms.
    public func get(_ coordinate: TileCoordinate) async -> Data? {
        // TODO: Implement — SQLite SELECT by (z, x, y), update last_accessed
        fatalError("Not yet implemented — implement for CG-002")
    }

    /// Store a tile in the cache. Triggers eviction if over capacity.
    /// Target: < 10ms.
    public func put(_ coordinate: TileCoordinate, data: Data) async {
        // TODO: Implement — SQLite INSERT OR REPLACE, check size, evict if needed
        fatalError("Not yet implemented — implement for CG-002")
    }

    /// Evict oldest tiles when cache exceeds maxCacheSize.
    /// Removes oldest 20% by last_accessed timestamp.
    public func evictIfNeeded() async {
        // TODO: Implement — check total BLOB size, DELETE oldest 20%
        fatalError("Not yet implemented — implement for CG-002")
    }

    /// Current cache size in bytes.
    public func currentSize() async -> Int {
        // TODO: Implement — SUM(length(data)) from tiles
        fatalError("Not yet implemented — implement for CG-002")
    }

    /// Number of cached tiles.
    public func tileCount() async -> Int {
        // TODO: Implement — COUNT(*) from tiles
        fatalError("Not yet implemented — implement for CG-002")
    }
}
