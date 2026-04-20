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

    // MARK: - Metadata API (CHA-150)

    func testTotalSize_Empty_ReturnsZero() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let total = await cache.totalSize()
        XCTAssertEqual(total, 0)
    }

    func testTotalSize_MatchesCurrentSize_AsInt64() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let data = Data(repeating: 0xFF, count: 1000)

        await cache.put(TileCoordinate(z: 10, x: 0, y: 0), data: data)
        await cache.put(TileCoordinate(z: 10, x: 1, y: 0), data: data)

        let total = await cache.totalSize()
        let current = await cache.currentSize()
        XCTAssertEqual(total, Int64(current))
        XCTAssertEqual(total, 2000)
    }

    func testLastUpdated_Empty_ReturnsNil() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let updated = await cache.lastUpdated()
        XCTAssertNil(updated)
    }

    func testLastUpdated_AfterPut_ReturnsRecentDate() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let data = Data(repeating: 0xAA, count: 64)

        let before = Date()
        await cache.put(TileCoordinate(z: 10, x: 0, y: 0), data: data)
        let after = Date()

        guard let updated = await cache.lastUpdated() else {
            XCTFail("lastUpdated() returned nil after put")
            return
        }

        // Allow 1s slack on both ends for ms-truncation and clock skew.
        XCTAssertGreaterThanOrEqual(updated.timeIntervalSince1970, before.timeIntervalSince1970 - 1)
        XCTAssertLessThanOrEqual(updated.timeIntervalSince1970, after.timeIntervalSince1970 + 1)
    }

    func testLastUpdated_TracksMaxAcrossTiles() async {
        let cache = TileCache(maxCacheSize: 10 * 1024 * 1024)
        let data = Data(repeating: 0xAA, count: 64)

        await cache.put(TileCoordinate(z: 10, x: 0, y: 0), data: data)
        try? await Task.sleep(nanoseconds: 15_000_000) // 15ms
        await cache.put(TileCoordinate(z: 10, x: 1, y: 0), data: data)

        let updated = await cache.lastUpdated()
        XCTAssertNotNil(updated)

        // Reading the older tile must not rewind lastUpdated past the newer write.
        _ = await cache.get(TileCoordinate(z: 10, x: 0, y: 0))
        let updated2 = await cache.lastUpdated()
        XCTAssertNotNil(updated2)
        if let u1 = updated, let u2 = updated2 {
            XCTAssertGreaterThanOrEqual(u2.timeIntervalSince1970, u1.timeIntervalSince1970)
        }
    }

    // MARK: - Metadata Bench (CHA-150)
    // Per docs/CLAUDE.md tile cache read target (< 5ms). Populates 10k rows
    // then asserts median over N=20 runs stays under the budget for both
    // totalSize() and lastUpdated().

    func testMetadataAPI_Bench_10kTiles_Under5msMedian() async {
        let cache = TileCache(maxCacheSize: 5 * 1024 * 1024 * 1024) // 5GB, avoid eviction
        let tile = Data(repeating: 0xCD, count: 64)

        // 10k synthetic tiles across a few zoom bands.
        for i in 0..<10_000 {
            let z = 10 + (i % 4)
            let x = i % 1024
            let y = i / 1024
            await cache.put(TileCoordinate(z: z, x: x, y: y), data: tile)
        }

        let tileCount = await cache.tileCount()
        XCTAssertEqual(tileCount, 10_000)

        let runs = 20
        var totalSizeSamples: [Double] = []
        var lastUpdatedSamples: [Double] = []
        totalSizeSamples.reserveCapacity(runs)
        lastUpdatedSamples.reserveCapacity(runs)

        for _ in 0..<runs {
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = await cache.totalSize()
            let t1 = CFAbsoluteTimeGetCurrent()
            _ = await cache.lastUpdated()
            let t2 = CFAbsoluteTimeGetCurrent()

            totalSizeSamples.append((t1 - t0) * 1000.0)
            lastUpdatedSamples.append((t2 - t1) * 1000.0)
        }

        let totalSizeMedian = median(totalSizeSamples)
        let lastUpdatedMedian = median(lastUpdatedSamples)

        XCTAssertLessThan(totalSizeMedian, 5.0,
            "totalSize() median \(totalSizeMedian)ms exceeds 5ms target (10k tiles)")
        XCTAssertLessThan(lastUpdatedMedian, 5.0,
            "lastUpdated() median \(lastUpdatedMedian)ms exceeds 5ms target (10k tiles)")
    }

    private func median(_ samples: [Double]) -> Double {
        precondition(!samples.isEmpty)
        let sorted = samples.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
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
