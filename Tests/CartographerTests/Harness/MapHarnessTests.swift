// MARK: - Map UI Harness Tests
// Defines the behavioral contract for the MapCoordinator + MapView layer.
// RULE: Never modify this file to make tests pass. Fix the implementation.

import XCTest
@testable import Cartographer
#if canImport(MapKit)
@preconcurrency import MapKit
#endif

final class MapHarnessTests: XCTestCase {

    // MARK: - Geometry helpers

    #if canImport(MapKit)

    func testBoundingBox_FromRegion_Symmetric() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 4.0)
        )
        let bbox = MapCoordinator.boundingBox(for: region)
        XCTAssertEqual(bbox.minLatitude,  39.0, accuracy: 1e-9)
        XCTAssertEqual(bbox.maxLatitude,  41.0, accuracy: 1e-9)
        XCTAssertEqual(bbox.minLongitude, -76.0, accuracy: 1e-9)
        XCTAssertEqual(bbox.maxLongitude, -72.0, accuracy: 1e-9)
        XCTAssertTrue(bbox.contains(GeoCoordinate(latitude: 40, longitude: -74)))
    }

    func testZoom_FromRegion_IncreasesAsSpanShrinks() {
        let wide = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
        )
        let narrow = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        let zWide = MapCoordinator.zoom(for: wide)
        let zNarrow = MapCoordinator.zoom(for: narrow)
        XCTAssertLessThan(zWide, zNarrow, "Narrower spans must map to higher slippy zooms")
        XCTAssertEqual(zWide, 0, "360° span is slippy zoom 0")
        XCTAssertGreaterThanOrEqual(zNarrow, 11)
    }

    #endif

    // MARK: - Visible-set diff

    func testMapVisibleDiff_AddedRemovedRetained() {
        let a = EntityID(), b = EntityID(), c = EntityID(), d = EntityID()
        let diff = MapVisibleDiff(previous: [a, b, c], current: [b, c, d])
        XCTAssertEqual(diff.added, [d])
        XCTAssertEqual(diff.removed, [a])
        XCTAssertEqual(diff.retained, [b, c])
    }

    func testMapVisibleDiff_EmptyWhenUnchanged() {
        let a = EntityID(), b = EntityID()
        let diff = MapVisibleDiff(previous: [a, b], current: [a, b])
        XCTAssertTrue(diff.isEmpty)
    }

    // MARK: - Clusterer

    func testClusterer_CollocatedPinsCollapseToSingleCluster() {
        let cell = 1.0
        let ids = (0..<5).map { _ in EntityID() }
        let items = ids.map { id in (id, GeoCoordinate(latitude: 0.1, longitude: 0.1)) }
        let clusters = MapClusterer.cluster(annotations: items, cellSizeDegrees: cell)
        XCTAssertEqual(clusters.count, 1, "Five pins in one cell must collapse to one cluster")
        XCTAssertEqual(clusters[0].memberIDs.count, 5)
        XCTAssertTrue(clusters[0].isCluster)
        XCTAssertTrue(clusters[0].boundingBox.contains(GeoCoordinate(latitude: 0.1, longitude: 0.1)))
    }

    func testClusterer_SeparatedCellsProduceSeparateClusters() {
        let cell = 1.0
        let a = EntityID(), b = EntityID()
        let items: [(EntityID, GeoCoordinate)] = [
            (a, GeoCoordinate(latitude: 0.5, longitude: 0.5)),
            (b, GeoCoordinate(latitude: 10.5, longitude: 10.5)),
        ]
        let clusters = MapClusterer.cluster(annotations: items, cellSizeDegrees: cell)
        XCTAssertEqual(clusters.count, 2)
        for cluster in clusters {
            XCTAssertEqual(cluster.memberIDs.count, 1)
            XCTAssertFalse(cluster.isCluster)
        }
    }

    func testClusterer_SingleMemberClusterPreservesAnnotationID() {
        let cell = 1.0
        let id = EntityID()
        let items: [(EntityID, GeoCoordinate)] = [(id, GeoCoordinate(latitude: 0, longitude: 0))]
        let clusters = MapClusterer.cluster(annotations: items, cellSizeDegrees: cell)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].id, id, "Degenerate cluster must carry the annotation's own id for stable diffing")
    }

    func testClusterer_IsDeterministic() {
        let cell = 1.0
        let seedIDs = (0..<50).map { _ in EntityID() }
        let items = seedIDs.enumerated().map { idx, id in
            (id, GeoCoordinate(
                latitude: Double(idx % 10) + 0.1,
                longitude: Double(idx / 10) + 0.1
            ))
        }
        let first  = MapClusterer.cluster(annotations: items, cellSizeDegrees: cell)
        let second = MapClusterer.cluster(annotations: items, cellSizeDegrees: cell)
        XCTAssertEqual(first.map(\.id), second.map(\.id),
                       "Same input must produce the same cluster id ordering")
        XCTAssertEqual(first.map(\.memberIDs.count), second.map(\.memberIDs.count))
    }

    // MARK: - MapCoordinator op-log invariant
    //
    // Every user mutation MUST go through AnnotationEngine → OperationLog.
    // The harness asserts this by inspecting the log after each gesture.

    #if canImport(MapKit)

    @MainActor
    func testCoordinator_BackgroundTap_AppendsInsertOperation() async throws {
        let (coordinator, log, projectID) = try await makeCoordinator()
        let before = try await log.operationCount(for: projectID)
        let id = await coordinator.handleBackgroundTap(
            at: GeoCoordinate(latitude: 10, longitude: 10)
        )
        XCTAssertNotNil(id, "Tap in an empty draft must create a pin")
        let after = try await log.operationCount(for: projectID)
        XCTAssertEqual(after - before, 1, "A background tap must produce exactly one operation")

        let lastOp = try await log.lastOperation(for: projectID)
        XCTAssertEqual(lastOp?.type, .insert)
        XCTAssertEqual(lastOp?.entityType, .annotation)
    }

    @MainActor
    func testCoordinator_LongPressThenDoubleTap_CreatesRouteOperation() async throws {
        let (coordinator, log, projectID) = try await makeCoordinator()
        coordinator.handleLongPress(at: GeoCoordinate(latitude: 10.0, longitude: 10.0))
        XCTAssertNotNil(coordinator.routeDraft, "Long-press must start a route draft")
        _ = await coordinator.handleBackgroundTap(
            at: GeoCoordinate(latitude: 10.1, longitude: 10.1)
        )
        XCTAssertEqual(coordinator.routeDraft?.coordinates.count, 2,
                       "Tap during a draft must append a waypoint, not create a pin")

        let before = try await log.operationCount(for: projectID)
        _ = await coordinator.handleDoubleTap(
            at: GeoCoordinate(latitude: 10.2, longitude: 10.2)
        )
        let after = try await log.operationCount(for: projectID)
        XCTAssertEqual(after - before, 1, "Double-tap commit must produce exactly one operation")
        XCTAssertNil(coordinator.routeDraft, "Route draft must clear on commit")

        let lastOp = try await log.lastOperation(for: projectID)
        XCTAssertEqual(lastOp?.type, .insert)
        XCTAssertEqual(lastOp?.entityType, .annotation)
    }

    @MainActor
    func testCoordinator_ClusterSelect_SingleMemberSelects_MultiMemberZooms() async throws {
        let (coordinator, _, _) = try await makeCoordinator()

        let lone = EntityID()
        var selectedID: EntityID?
        var zoomedBox: BoundingBox?
        coordinator.onSelectAnnotation = { selectedID = $0 }
        coordinator.onRequestZoom = { zoomedBox = $0 }

        let single = MapCluster(
            id: lone,
            coordinate: GeoCoordinate(latitude: 1, longitude: 1),
            boundingBox: BoundingBox(minLatitude: 1, maxLatitude: 1, minLongitude: 1, maxLongitude: 1),
            memberIDs: [lone]
        )
        coordinator.handleClusterSelect(single)
        XCTAssertEqual(selectedID, lone)
        XCTAssertNil(zoomedBox)

        let many = MapCluster(
            id: EntityID(),
            coordinate: GeoCoordinate(latitude: 5, longitude: 5),
            boundingBox: BoundingBox(minLatitude: 4, maxLatitude: 6, minLongitude: 4, maxLongitude: 6),
            memberIDs: [EntityID(), EntityID(), EntityID()]
        )
        coordinator.handleClusterSelect(many)
        XCTAssertEqual(zoomedBox, many.boundingBox)
    }

    @MainActor
    func testCoordinator_RefreshVisibleSet_DiffsAgainstPrevious() async throws {
        let (coordinator, _, projectID) = try await makeCoordinator()
        // Create two pins in distinct regions.
        let near = try await coordinator.annotationEngine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.0, longitude: -74.0),
            projectID: projectID
        )
        let far = try await coordinator.annotationEngine.create(
            type: .pin,
            coordinate: GeoCoordinate(latitude: -40.0, longitude: 74.0),
            projectID: projectID
        )

        let nearRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: -74),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        let diff1 = await coordinator.refreshVisibleSet(region: nearRegion, coordinateProvider: nil)
        XCTAssertTrue(diff1.added.contains(near.id))
        XCTAssertFalse(diff1.added.contains(far.id))
        XCTAssertTrue(coordinator.visibleAnnotationIDs.contains(near.id))

        let farRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -40, longitude: 74),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        let diff2 = await coordinator.refreshVisibleSet(region: farRegion, coordinateProvider: nil)
        XCTAssertTrue(diff2.added.contains(far.id))
        XCTAssertTrue(diff2.removed.contains(near.id))
    }

    @MainActor
    func testCoordinator_ComputeClusters_RespectsZoomThreshold() async throws {
        let (coordinator, _, projectID) = try await makeCoordinator()
        let a = try await coordinator.annotationEngine.create(
            type: .pin, coordinate: GeoCoordinate(latitude: 40.1, longitude: -74.1),
            projectID: projectID)
        let b = try await coordinator.annotationEngine.create(
            type: .pin, coordinate: GeoCoordinate(latitude: 40.2, longitude: -74.2),
            projectID: projectID)
        let visible = [a.id, b.id]
        let coords: [EntityID: GeoCoordinate] = [a.id: a.coordinate, b.id: b.coordinate]

        // At high zoom, no clustering — one cluster per pin.
        let high = coordinator.computeClusters(visibleIDs: visible, zoom: 15, coordinates: coords)
        XCTAssertEqual(high.count, 2)
        XCTAssertTrue(high.allSatisfy { !$0.isCluster })

        // At low zoom, clustering kicks in — pins within a shared cell collapse.
        let low = coordinator.computeClusters(visibleIDs: visible, zoom: 4, coordinates: coords)
        XCTAssertLessThanOrEqual(low.count, 2)
        let totalMembers = low.reduce(0) { $0 + $1.memberIDs.count }
        XCTAssertEqual(totalMembers, 2, "Clustering must preserve member set")
    }

    @MainActor
    func testCoordinator_DeleteAnnotation_RemovesFromVisibleSet() async throws {
        let (coordinator, _, projectID) = try await makeCoordinator()
        let pin = try await coordinator.annotationEngine.create(
            type: .pin, coordinate: GeoCoordinate(latitude: 0, longitude: 0),
            projectID: projectID)
        let worldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
        )
        _ = await coordinator.refreshVisibleSet(region: worldRegion, coordinateProvider: nil)
        XCTAssertTrue(coordinator.visibleAnnotationIDs.contains(pin.id))
        await coordinator.deleteAnnotation(pin.id)
        XCTAssertFalse(coordinator.visibleAnnotationIDs.contains(pin.id))
    }

    // MARK: - Performance

    @MainActor
    func testCoordinator_RefreshVisibleSet_5KAnnotations_Under16ms() async throws {
        // PRD CG-006: < 16ms frame time during pan with 5K annotations visible.
        // This harness exercises the viewport-update path — spatial query +
        // diff + clustering — which is what runs on every `regionDidChange`.
        // Pin sampling uses a deterministic grid so every run measures the
        // same worst-case mix.
        let (coordinator, _, projectID) = try await makeCoordinator()
        let engine = coordinator.annotationEngine

        // Seed 5,000 annotations spread across a 10° × 10° box.
        var coords: [EntityID: GeoCoordinate] = [:]
        let seedRegion = BoundingBox(minLatitude: 35, maxLatitude: 45, minLongitude: -80, maxLongitude: -70)
        var inserted: [Annotation] = []
        inserted.reserveCapacity(5_000)
        for i in 0..<5_000 {
            let lat = seedRegion.minLatitude + Double(i % 100) * 0.1
            let lon = seedRegion.minLongitude + Double(i / 100) * 0.1
            let a = try await engine.create(
                type: .pin,
                coordinate: GeoCoordinate(latitude: lat, longitude: lon),
                projectID: projectID
            )
            coords[a.id] = a.coordinate
            inserted.append(a)
        }

        let viewport = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: -75),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
        )

        // Warm up (JIT, caches).
        _ = await coordinator.refreshVisibleSet(region: viewport, coordinateProvider: coords)

        let start = DispatchTime.now()
        _ = await coordinator.refreshVisibleSet(region: viewport, coordinateProvider: coords)
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsedNs) / 1_000_000.0

        // CI-tolerant ceiling: the PRD target is 16ms, we accept up to 80ms
        // on noisy shared runners (same pattern as BenchmarkTests).
        XCTAssertLessThan(elapsedMs, 80,
                          "refreshVisibleSet for 5K annotations took \(elapsedMs) ms (budget 16ms, CI ceiling 80ms)")
        XCTAssertGreaterThanOrEqual(coordinator.visibleAnnotationIDs.count, 4_900,
                                    "Viewport covers the seeded grid; expected most pins visible")
    }

    #endif

    // MARK: - Fixtures

    #if canImport(MapKit)
    @MainActor
    private func makeCoordinator() async throws -> (MapCoordinator, OperationLog, EntityID) {
        let log = OperationLog(path: nil)
        let clock = HLCClock()
        let engine = AnnotationEngine(clock: clock, operationLog: log)
        let cache = TileCache(maxCacheSize: 1 * 1024 * 1024, path: ":memory:")
        let overlay = CachingTileOverlay(
            source: OpenStreetMapTileSource(),
            cache: cache,
            session: .shared
        )
        let projectID = EntityID()
        let coordinator = MapCoordinator(
            annotationEngine: engine,
            tileOverlay: overlay,
            projectID: projectID
        )
        return (coordinator, log, projectID)
    }
    #endif
}

// MARK: - OperationLog test helpers

/// Tuple-shaped metadata so the harness avoids naming `Cartographer.Operation`,
/// which collides with Foundation's `NSOperation` at the unqualified site and
/// with the `Cartographer` struct at the qualified site.
struct LastOperationInfo {
    let type: OperationType
    let entityType: EntityType
}

private extension OperationLog {
    func operationCount(for projectID: EntityID) throws -> Int {
        try materializeProject(projectID: projectID).count
    }

    func lastOperation(for projectID: EntityID) throws -> LastOperationInfo? {
        // `unsynced()` returns operations in HLC order, which is what we want.
        let ops = try unsynced()
        guard let last = ops.filter({ $0.projectID == projectID }).last else { return nil }
        return LastOperationInfo(type: last.type, entityType: last.entityType)
    }
}
