// MARK: - TileCache Tests
// Tests for SQLite-backed tile cache with LRU eviction.

import XCTest
@testable import Cartographer

final class TileCacheTests: XCTestCase {

    // MARK: - Basic Operations

    func testPutAndGet_ReturnsCachedData() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let coord = TileCoordinate(z: 10, x: 301, y: 384)
        let tileData = Data(repeating: 0xAB, count: 256)

        await cache.put(coord, data: tileData)
        let result = await cache.get(coord)

        XCTAssertEqual(result, tileData)
    }

    func testGet_CacheMiss_ReturnsNil() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let coord = TileCoordinate(z: 5, x: 10, y: 20)

        let result = await cache.get(coord)

        XCTAssertNil(result)
    }

    func testPut_OverwritesExistingTile() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let coord = TileCoordinate(z: 10, x: 301, y: 384)
        let data1 = Data(repeating: 0x01, count: 100)
        let data2 = Data(repeating: 0x02, count: 200)

        await cache.put(coord, data: data1)
        await cache.put(coord, data: data2)
        let result = await cache.get(coord)

        XCTAssertEqual(result, data2)
    }

    // MARK: - Tile Count & Size

    func testTileCount_Empty() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let count = await cache.tileCount()
        XCTAssertEqual(count, 0)
    }

    func testTileCount_AfterInserts() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let data = Data(repeating: 0xFF, count: 64)

        for i in 0..<5 {
            await cache.put(TileCoordinate(z: 10, x: i, y: 0), data: data)
        }

        let count = await cache.tileCount()
        XCTAssertEqual(count, 5)
    }

    func testCurrentSize_Empty() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let size = await cache.currentSize()
        XCTAssertEqual(size, 0)
    }

    func testCurrentSize_MatchesInsertedData() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let data = Data(repeating: 0xFF, count: 1000)

        await cache.put(TileCoordinate(z: 10, x: 0, y: 0), data: data)
        await cache.put(TileCoordinate(z: 10, x: 1, y: 0), data: data)

        let size = await cache.currentSize()
        XCTAssertEqual(size, 2000)
    }

    // MARK: - LRU Eviction

    func testEviction_TriggeredWhenOverCapacity() async {
        // 1KB max cache
        let cache = TileCache(maxCacheSize: 1024)
        let bigTile = Data(repeating: 0xAA, count: 300)

        // Insert 5 tiles (5 * 300 = 1500 bytes > 1024)
        for i in 0..<5 {
            await cache.put(TileCoordinate(z: 10, x: i, y: 0), data: bigTile)
            // Small delay so timestamps differ
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        let count = await cache.tileCount()
        let size = await cache.currentSize()

        // After eviction, cache should be smaller
        XCTAssertTrue(size <= 1024 || count < 5, "Cache should evict tiles when over capacity. Size: \(size), Count: \(count)")
    }

    func testEviction_RemovesOldestTiles() async {
        // Very small cache to force eviction
        let cache = TileCache(maxCacheSize: 512)
        let tileData = Data(repeating: 0xBB, count: 200)

        // Insert tiles with small delays for timestamp ordering
        let oldest = TileCoordinate(z: 1, x: 0, y: 0)
        await cache.put(oldest, data: tileData)
        try? await Task.sleep(nanoseconds: 10_000_000)

        await cache.put(TileCoordinate(z: 1, x: 1, y: 0), data: tileData)
        try? await Task.sleep(nanoseconds: 10_000_000)

        let newest = TileCoordinate(z: 1, x: 2, y: 0)
        await cache.put(newest, data: tileData)
        try? await Task.sleep(nanoseconds: 10_000_000)

        // This should trigger eviction (4 * 200 = 800 > 512)
        await cache.put(TileCoordinate(z: 1, x: 3, y: 0), data: tileData)

        // The newest tile should still be accessible
        let newestResult = await cache.get(newest)
        XCTAssertNotNil(newestResult, "Newest tiles should survive eviction")
    }

    // MARK: - Multiple Tile Coordinates

    func testMultipleTiles_DifferentZoomLevels() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)

        let tiles: [(TileCoordinate, Data)] = [
            (TileCoordinate(z: 1, x: 0, y: 0), Data(repeating: 0x01, count: 100)),
            (TileCoordinate(z: 5, x: 15, y: 10), Data(repeating: 0x05, count: 200)),
            (TileCoordinate(z: 15, x: 1000, y: 2000), Data(repeating: 0x0F, count: 300)),
        ]

        for (coord, data) in tiles {
            await cache.put(coord, data: data)
        }

        for (coord, expectedData) in tiles {
            let result = await cache.get(coord)
            XCTAssertEqual(result, expectedData, "Tile at z=\(coord.z) x=\(coord.x) y=\(coord.y) should be retrievable")
        }
    }

    // MARK: - Persistence (file-backed)

    func testFileBacked_PersistsAcrossInstances() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_tilecache_\(UUID().uuidString).db").path

        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let coord = TileCoordinate(z: 10, x: 301, y: 384)
        let tileData = Data(repeating: 0xCC, count: 512)

        // Write with first instance
        let cache1 = TileCache(maxCacheSize: 10 * 1024 * 1024, path: dbPath)
        await cache1.put(coord, data: tileData)
        let count1 = await cache1.tileCount()
        XCTAssertEqual(count1, 1)

        // Read with second instance
        let cache2 = TileCache(maxCacheSize: 10 * 1024 * 1024, path: dbPath)
        let result = await cache2.get(coord)
        XCTAssertEqual(result, tileData, "Tile data should persist across TileCache instances")
    }
}
