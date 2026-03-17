// MARK: - R-Tree Harness Tests
// Defines the complete behavioral contract for the spatial index.
// RULE: Never modify this file to make tests pass. Fix the implementation instead.

import XCTest
@testable import Cartographer

final class RTreeHarnessTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(_ id: Int, lat: Double, lon: Double) -> RTreeEntry<Int> {
        RTreeEntry(element: id, boundingBox: BoundingBox(
            minLatitude: lat, maxLatitude: lat,
            minLongitude: lon, maxLongitude: lon
        ))
    }

    private func makeBoxEntry(_ id: Int, minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) -> RTreeEntry<Int> {
        RTreeEntry(element: id, boundingBox: BoundingBox(
            minLatitude: minLat, maxLatitude: maxLat,
            minLongitude: minLon, maxLongitude: maxLon
        ))
    }

    // MARK: - Insert Tests

    func testInsert_SingleEntry() {
        var tree = RTree<Int>(maxEntries: 4)
        tree.insert(makeEntry(1, lat: 40.0, lon: -74.0))
        XCTAssertEqual(tree.count, 1)
        XCTAssertFalse(tree.isEmpty)
    }

    func testInsert_MultipleEntries() {
        var tree = RTree<Int>(maxEntries: 4)
        for i in 0..<100 {
            tree.insert(makeEntry(i, lat: Double(i) * 0.1, lon: Double(i) * 0.1))
        }
        XCTAssertEqual(tree.count, 100)
    }

    func testInsert_TriggersNodeSplit() {
        var tree = RTree<Int>(maxEntries: 4)
        // Insert more than maxEntries to force a split
        for i in 0..<10 {
            tree.insert(makeEntry(i, lat: Double(i), lon: Double(i)))
        }
        XCTAssertEqual(tree.count, 10)
        // After split, root should be internal (not leaf)
        if case .leaf = tree.root {
            XCTFail("Root should be internal node after split")
        }
    }

    // MARK: - Search Tests

    func testSearch_FindsIntersecting() {
        var tree = RTree<Int>(maxEntries: 4)
        // Points scattered around origin
        tree.insert(makeEntry(1, lat: 1.0, lon: 1.0))
        tree.insert(makeEntry(2, lat: 2.0, lon: 2.0))
        tree.insert(makeEntry(3, lat: 10.0, lon: 10.0))

        let queryBox = BoundingBox(minLatitude: 0.5, maxLatitude: 2.5, minLongitude: 0.5, maxLongitude: 2.5)
        let results = tree.search(in: queryBox)

        let ids = Set(results.map(\.element))
        XCTAssertTrue(ids.contains(1))
        XCTAssertTrue(ids.contains(2))
        XCTAssertFalse(ids.contains(3), "Point at (10,10) should not be in query box")
    }

    func testSearch_EmptyTree() {
        let tree = RTree<Int>(maxEntries: 4)
        let results = tree.search(in: BoundingBox(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10))
        XCTAssertTrue(results.isEmpty)
    }

    func testSearch_BoxIntersectsBox() {
        var tree = RTree<Int>(maxEntries: 4)
        tree.insert(makeBoxEntry(1, minLat: 0, maxLat: 5, minLon: 0, maxLon: 5))

        // Partial overlap
        let query = BoundingBox(minLatitude: 3, maxLatitude: 8, minLongitude: 3, maxLongitude: 8)
        let results = tree.search(in: query)
        XCTAssertEqual(results.count, 1)
    }

    func testSearch_GlobalQuery_ReturnsAll() {
        var tree = RTree<Int>(maxEntries: 4)
        for i in 0..<50 {
            tree.insert(makeEntry(i, lat: Double.random(in: -90...90), lon: Double.random(in: -180...180)))
        }
        let allBox = BoundingBox(minLatitude: -90, maxLatitude: 90, minLongitude: -180, maxLongitude: 180)
        let results = tree.search(in: allBox)
        XCTAssertEqual(results.count, 50, "Global query must return all entries")
    }

    // MARK: - Delete Tests

    func testRemove_ExistingEntry() {
        var tree = RTree<Int>(maxEntries: 4)
        tree.insert(makeEntry(1, lat: 1.0, lon: 1.0))
        tree.insert(makeEntry(2, lat: 2.0, lon: 2.0))

        let removed = tree.remove(1)
        XCTAssertTrue(removed)
        XCTAssertEqual(tree.count, 1)

        let results = tree.search(in: BoundingBox(minLatitude: 0, maxLatitude: 3, minLongitude: 0, maxLongitude: 3))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.element, 2)
    }

    func testRemove_NonExistent() {
        var tree = RTree<Int>(maxEntries: 4)
        tree.insert(makeEntry(1, lat: 1.0, lon: 1.0))

        let removed = tree.remove(999)
        XCTAssertFalse(removed)
        XCTAssertEqual(tree.count, 1)
    }

    // MARK: - Nearest Neighbor Tests

    func testNearest_FindsClosest() {
        var tree = RTree<Int>(maxEntries: 4)
        tree.insert(makeEntry(1, lat: 10.0, lon: 10.0))
        tree.insert(makeEntry(2, lat: 20.0, lon: 20.0))
        tree.insert(makeEntry(3, lat: 30.0, lon: 30.0))

        let nearest = tree.nearest(to: GeoCoordinate(latitude: 11.0, longitude: 11.0))
        XCTAssertNotNil(nearest)
        XCTAssertEqual(nearest?.element, 1)
    }

    func testNearest_EmptyTree() {
        let tree = RTree<Int>(maxEntries: 4)
        let nearest = tree.nearest(to: GeoCoordinate(latitude: 0, longitude: 0))
        XCTAssertNil(nearest)
    }

    // MARK: - Bulk Load Tests

    func testBulkLoad_CorrectCount() {
        let entries = (0..<1000).map { i in
            makeEntry(i, lat: Double.random(in: -90...90), lon: Double.random(in: -180...180))
        }
        let tree = RTree.bulkLoad(entries, maxEntries: 16)
        XCTAssertEqual(tree.count, 1000)
    }

    func testBulkLoad_AllSearchable() {
        let entries = (0..<500).map { i in
            makeEntry(i, lat: Double.random(in: -90...90), lon: Double.random(in: -180...180))
        }
        let tree = RTree.bulkLoad(entries, maxEntries: 16)
        let allBox = BoundingBox(minLatitude: -90, maxLatitude: 90, minLongitude: -180, maxLongitude: 180)
        let results = tree.search(in: allBox)
        XCTAssertEqual(results.count, 500, "All bulk-loaded entries must be searchable")
    }

    func testBulkLoad_EmptyInput() {
        let tree = RTree<Int>.bulkLoad([], maxEntries: 16)
        XCTAssertEqual(tree.count, 0)
        XCTAssertTrue(tree.isEmpty)
    }

    // MARK: - Stress Tests

    func testStress_InsertDeleteSearch_10K() {
        var tree = RTree<Int>(maxEntries: 16)
        let n = 10_000

        // Insert 10K random points
        for i in 0..<n {
            tree.insert(makeEntry(i, lat: Double.random(in: -90...90), lon: Double.random(in: -180...180)))
        }
        XCTAssertEqual(tree.count, n)

        // Delete half
        for i in stride(from: 0, to: n, by: 2) {
            tree.remove(i)
        }
        XCTAssertEqual(tree.count, n / 2)

        // All remaining should be searchable
        let allBox = BoundingBox(minLatitude: -90, maxLatitude: 90, minLongitude: -180, maxLongitude: 180)
        let results = tree.search(in: allBox)
        XCTAssertEqual(results.count, n / 2)
    }
}
