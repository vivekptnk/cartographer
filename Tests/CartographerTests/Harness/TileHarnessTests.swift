// MARK: - Tile Engine Harness Tests
// Defines the behavioral contract for tile caching, coordinate math, and overlay.
// RULE: Never modify this file to make tests pass. Fix the implementation instead.

import XCTest
@testable import Cartographer

final class TileHarnessTests: XCTestCase {

    // MARK: - TileCoordinate Math

    func testTileCoordinate_FromCoordinate_Zoom0() {
        // At zoom 0, the entire world is one tile (0, 0, 0)
        let tile = TileCoordinate.from(
            coordinate: GeoCoordinate(latitude: 0, longitude: 0),
            zoom: 0
        )
        XCTAssertEqual(tile.z, 0)
        XCTAssertEqual(tile.x, 0)
        XCTAssertEqual(tile.y, 0)
    }

    func testTileCoordinate_FromCoordinate_NYC() {
        // NYC ~(40.7128, -74.0060) at zoom 10
        let tile = TileCoordinate.from(
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            zoom: 10
        )
        XCTAssertEqual(tile.z, 10)
        // Known tile coords for NYC at z=10: x=301, y=384 (approximately)
        XCTAssertTrue((300...302).contains(tile.x), "NYC x tile should be ~301 at z=10, got \(tile.x)")
        XCTAssertTrue((383...385).contains(tile.y), "NYC y tile should be ~384 at z=10, got \(tile.y)")
    }

    func testTileCoordinate_BoundingBox_ContainsOriginalPoint() {
        let coord = GeoCoordinate(latitude: 48.8566, longitude: 2.3522) // Paris
        let tile = TileCoordinate.from(coordinate: coord, zoom: 12)
        let bbox = tile.boundingBox
        XCTAssertTrue(bbox.contains(coord), "Tile bounding box must contain the coordinate that generated it")
    }

    func testTileCoordinate_TilesPerAxis() {
        XCTAssertEqual(TileCoordinate(z: 0, x: 0, y: 0).tilesPerAxis, 1)
        XCTAssertEqual(TileCoordinate(z: 1, x: 0, y: 0).tilesPerAxis, 2)
        XCTAssertEqual(TileCoordinate(z: 10, x: 0, y: 0).tilesPerAxis, 1024)
    }

    // MARK: - BoundingBox Tests

    func testBoundingBox_Intersects() {
        let a = BoundingBox(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10)
        let b = BoundingBox(minLatitude: 5, maxLatitude: 15, minLongitude: 5, maxLongitude: 15)
        XCTAssertTrue(a.intersects(b))
        XCTAssertTrue(b.intersects(a), "Intersection must be symmetric")
    }

    func testBoundingBox_DoesNotIntersect() {
        let a = BoundingBox(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10)
        let b = BoundingBox(minLatitude: 20, maxLatitude: 30, minLongitude: 20, maxLongitude: 30)
        XCTAssertFalse(a.intersects(b))
    }

    func testBoundingBox_Contains() {
        let box = BoundingBox(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10)
        XCTAssertTrue(box.contains(GeoCoordinate(latitude: 5, longitude: 5)))
        XCTAssertTrue(box.contains(GeoCoordinate(latitude: 0, longitude: 0)), "Boundary should be inclusive")
        XCTAssertFalse(box.contains(GeoCoordinate(latitude: 15, longitude: 5)))
    }

    func testBoundingBox_Union() {
        let a = BoundingBox(minLatitude: 0, maxLatitude: 5, minLongitude: 0, maxLongitude: 5)
        let b = BoundingBox(minLatitude: 3, maxLatitude: 10, minLongitude: 3, maxLongitude: 10)
        let u = a.union(b)
        XCTAssertEqual(u.minLatitude, 0)
        XCTAssertEqual(u.maxLatitude, 10)
        XCTAssertEqual(u.minLongitude, 0)
        XCTAssertEqual(u.maxLongitude, 10)
    }

    func testBoundingBox_Area() {
        let box = BoundingBox(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10)
        XCTAssertEqual(box.area, 100.0, accuracy: 0.001)
    }

    // MARK: - Annotation BoundingBox

    func testAnnotation_PinBoundingBox_IsPoint() {
        let pin = Annotation(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.0, longitude: -74.0),
            projectID: UUID()
        )
        let bbox = pin.boundingBox
        XCTAssertEqual(bbox.minLatitude, bbox.maxLatitude)
        XCTAssertEqual(bbox.minLongitude, bbox.maxLongitude)
    }

    func testAnnotation_RouteBoundingBox_EnclosesAllPoints() {
        let coords = [
            GeoCoordinate(latitude: 10, longitude: 20),
            GeoCoordinate(latitude: 30, longitude: 40),
            GeoCoordinate(latitude: 5, longitude: 50),
        ]
        let route = Annotation(
            type: .route,
            coordinate: coords[0],
            routeCoordinates: coords,
            projectID: UUID()
        )
        let bbox = route.boundingBox
        for coord in coords {
            XCTAssertTrue(bbox.contains(coord), "Route bbox must contain all route coordinates")
        }
    }

    // MARK: - Annotation Codable Round-Trip

    func testAnnotation_CodableRoundTrip_AllTypes() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in AnnotationType.allCases {
            let original = Annotation(
                type: type,
                coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
                title: "Test \(type.rawValue)",
                body: "Body text",
                routeCoordinates: type == .route ? [
                    GeoCoordinate(latitude: 40.7, longitude: -74.0),
                    GeoCoordinate(latitude: 40.8, longitude: -74.1),
                ] : nil,
                polygonCoordinates: type == .polygon ? [
                    GeoCoordinate(latitude: 40.7, longitude: -74.0),
                    GeoCoordinate(latitude: 40.8, longitude: -74.0),
                    GeoCoordinate(latitude: 40.8, longitude: -74.1),
                ] : nil,
                metadata: ["key": "value"],
                projectID: UUID()
            )

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(Annotation.self, from: data)

            XCTAssertEqual(decoded.id, original.id)
            XCTAssertEqual(decoded.type, original.type)
            XCTAssertEqual(decoded.coordinate, original.coordinate)
            XCTAssertEqual(decoded.title, original.title)
            XCTAssertEqual(decoded.body, original.body)
            XCTAssertEqual(decoded.routeCoordinates, original.routeCoordinates)
            XCTAssertEqual(decoded.polygonCoordinates, original.polygonCoordinates)
            XCTAssertEqual(decoded.metadata, original.metadata)
        }
    }
}
