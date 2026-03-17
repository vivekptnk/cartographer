// MARK: - AnnotationEngine CRUD Tests
// Validates create/update/delete round-trips through the operation log.
// Tests that mutations go through the operation log and R-tree stays in sync.

import XCTest
@testable import Cartographer

final class AnnotationEngineTests: XCTestCase {

    private func makeEngine() -> (AnnotationEngine, OperationLog, HLCClock) {
        let clock = HLCClock(nodeID: UUID())
        let log = OperationLog()
        let engine = AnnotationEngine(clock: clock, operationLog: log)
        return (engine, log, clock)
    }

    // MARK: - Create

    func testCreate_ReturnsAnnotation() async throws {
        let (engine, _, _) = makeEngine()
        let projectID = UUID()

        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            title: "NYC",
            body: "Test pin",
            projectID: projectID
        )

        XCTAssertEqual(annotation.type, .pin)
        XCTAssertEqual(annotation.title, "NYC")
        XCTAssertEqual(annotation.body, "Test pin")
        XCTAssertEqual(annotation.coordinate.latitude, 40.7128)
        XCTAssertEqual(annotation.coordinate.longitude, -74.0060)
        XCTAssertEqual(annotation.projectID, projectID)
    }

    func testCreate_AppendsToOperationLog() async throws {
        let (engine, log, _) = makeEngine()
        let projectID = UUID()

        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            projectID: projectID
        )

        // Materialize from the log — should produce the same annotation
        let materialized = try await log.materialize(entityID: annotation.id)
        XCTAssertNotNil(materialized)
        XCTAssertEqual(materialized?.id, annotation.id)
        XCTAssertEqual(materialized?.type, .pin)
        XCTAssertEqual(materialized?.coordinate.latitude, 40.7128)
    }

    func testCreate_InsertsIntoSpatialIndex() async throws {
        let (engine, _, _) = makeEngine()
        let projectID = UUID()

        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            projectID: projectID
        )

        // Query the spatial index for the region around the pin
        let box = BoundingBox(
            minLatitude: 40.0, maxLatitude: 41.0,
            minLongitude: -75.0, maxLongitude: -74.0
        )
        let found = await engine.annotations(in: box)
        XCTAssertTrue(found.contains(annotation.id))
    }

    func testCreate_MultipleAnnotations() async throws {
        let (engine, _, _) = makeEngine()
        let projectID = UUID()

        let a1 = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.0, longitude: -74.0),
            title: "A",
            projectID: projectID
        )
        let a2 = try await engine.create(
            type: .note,
            coordinate: GeoCoordinate(latitude: 41.0, longitude: -73.0),
            title: "B",
            projectID: projectID
        )

        XCTAssertNotEqual(a1.id, a2.id)

        // Both should be in the spatial index
        let bigBox = BoundingBox(
            minLatitude: 39.0, maxLatitude: 42.0,
            minLongitude: -75.0, maxLongitude: -72.0
        )
        let found = await engine.annotations(in: bigBox)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains(a1.id))
        XCTAssertTrue(found.contains(a2.id))
    }

    // MARK: - Update

    func testUpdate_Title() async throws {
        let (engine, log, _) = makeEngine()
        let projectID = UUID()

        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            title: "Original",
            projectID: projectID
        )

        try await engine.update(annotationID: annotation.id, title: "Updated")

        // Verify through operation log materialization
        let materialized = try await log.materialize(entityID: annotation.id)
        XCTAssertEqual(materialized?.title, "Updated")
    }

    func testUpdate_Body() async throws {
        let (engine, log, _) = makeEngine()
        let projectID = UUID()

        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            body: "Original body",
            projectID: projectID
        )

        try await engine.update(annotationID: annotation.id, body: "New body")

        let materialized = try await log.materialize(entityID: annotation.id)
        XCTAssertEqual(materialized?.body, "New body")
    }

    func testUpdate_Coordinate_UpdatesSpatialIndex() async throws {
        let (engine, _, _) = makeEngine()
        let projectID = UUID()

        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.0, longitude: -74.0),
            projectID: projectID
        )

        // Move to a different location
        let newCoord = GeoCoordinate(latitude: 50.0, longitude: -80.0)
        try await engine.update(annotationID: annotation.id, coordinate: newCoord)

        // Should NOT be found at old location
        let oldBox = BoundingBox(
            minLatitude: 39.0, maxLatitude: 41.0,
            minLongitude: -75.0, maxLongitude: -73.0
        )
        let oldResults = await engine.annotations(in: oldBox)
        XCTAssertFalse(oldResults.contains(annotation.id))

        // Should be found at new location
        let newBox = BoundingBox(
            minLatitude: 49.0, maxLatitude: 51.0,
            minLongitude: -81.0, maxLongitude: -79.0
        )
        let newResults = await engine.annotations(in: newBox)
        XCTAssertTrue(newResults.contains(annotation.id))
    }

    func testUpdate_NonExistentAnnotation_NoOp() async throws {
        let (engine, log, _) = makeEngine()

        // Updating a non-existent annotation should be a no-op
        try await engine.update(annotationID: UUID(), title: "Ghost")

        // Log should have no operations
        let unsynced = try await log.unsynced()
        XCTAssertTrue(unsynced.isEmpty)
    }

    // MARK: - Delete

    func testDelete_RemovesFromSpatialIndex() async throws {
        let (engine, _, _) = makeEngine()
        let projectID = UUID()

        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            projectID: projectID
        )

        try await engine.delete(annotationID: annotation.id, projectID: projectID)

        // Should no longer be found in spatial index
        let box = BoundingBox(
            minLatitude: 40.0, maxLatitude: 41.0,
            minLongitude: -75.0, maxLongitude: -74.0
        )
        let found = await engine.annotations(in: box)
        XCTAssertFalse(found.contains(annotation.id))
    }

    func testDelete_AppendsDeleteOperation() async throws {
        let (engine, log, _) = makeEngine()
        let projectID = UUID()

        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            projectID: projectID
        )

        try await engine.delete(annotationID: annotation.id, projectID: projectID)

        // Materializing a deleted annotation should return nil
        let materialized = try await log.materialize(entityID: annotation.id)
        XCTAssertNil(materialized)
    }

    func testDelete_ThenNearest_ReturnsNil() async throws {
        let (engine, _, _) = makeEngine()
        let projectID = UUID()

        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            projectID: projectID
        )

        try await engine.delete(annotationID: annotation.id, projectID: projectID)

        let nearest = await engine.nearest(to: GeoCoordinate(latitude: 40.7128, longitude: -74.0060))
        XCTAssertNil(nearest)
    }

    // MARK: - Round-Trip Integration

    func testCreateUpdateDelete_FullLifecycle() async throws {
        let (engine, log, _) = makeEngine()
        let projectID = UUID()

        // Create
        let annotation = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            title: "HQ",
            projectID: projectID
        )

        // Update
        try await engine.update(annotationID: annotation.id, title: "NYC HQ", body: "Main office")

        // Verify update in log
        let updated = try await log.materialize(entityID: annotation.id)
        XCTAssertEqual(updated?.title, "NYC HQ")
        XCTAssertEqual(updated?.body, "Main office")

        // Delete
        try await engine.delete(annotationID: annotation.id, projectID: projectID)

        // Verify deletion
        let deleted = try await log.materialize(entityID: annotation.id)
        XCTAssertNil(deleted)

        // Verify spatial index is clean
        let box = BoundingBox(
            minLatitude: 40.0, maxLatitude: 41.0,
            minLongitude: -75.0, maxLongitude: -74.0
        )
        let found = await engine.annotations(in: box)
        XCTAssertTrue(found.isEmpty)
    }

    func testOperationLog_RecordsAllMutations() async throws {
        let (engine, log, _) = makeEngine()
        let projectID = UUID()

        let a = try await engine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.0, longitude: -74.0),
            projectID: projectID
        )
        try await engine.update(annotationID: a.id, title: "Edited")
        try await engine.delete(annotationID: a.id, projectID: projectID)

        // Should have 3 unsynced operations: insert, update, delete
        let ops = try await log.unsynced()
        XCTAssertEqual(ops.count, 3)
        XCTAssertEqual(ops[0].type, .insert)
        XCTAssertEqual(ops[1].type, .update)
        XCTAssertEqual(ops[2].type, .delete)
    }

    // MARK: - Rebuild Index

    func testRebuildIndex_PopulatesAnnotationsCache() async throws {
        let (engine, _, _) = makeEngine()
        let projectID = UUID()

        // Simulate loading existing annotations (e.g., on app launch)
        let annotations = [
            Annotation(
                type: .pin,
                coordinate: GeoCoordinate(latitude: 40.0, longitude: -74.0),
                title: "A",
                projectID: projectID
            ),
            Annotation(
                type: .note,
                coordinate: GeoCoordinate(latitude: 41.0, longitude: -73.0),
                title: "B",
                projectID: projectID
            ),
        ]

        await engine.rebuildIndex(from: annotations)

        // Both should be queryable
        let bigBox = BoundingBox(
            minLatitude: 39.0, maxLatitude: 42.0,
            minLongitude: -75.0, maxLongitude: -72.0
        )
        let found = await engine.annotations(in: bigBox)
        XCTAssertEqual(found.count, 2)

        // Should be able to update an annotation loaded via rebuildIndex
        try await engine.update(annotationID: annotations[0].id, title: "Updated A")
    }
}
