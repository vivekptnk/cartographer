import XCTest
@testable import Cartographer
import Foundation

final class GeoJSONExporterTests: XCTestCase {

    let exporter = GeoJSONExporter()
    let projectID = UUID()

    // MARK: - Helpers

    private func makePin(title: String = "Test Pin", lat: Double = 37.7749, lon: Double = -122.4194) -> Annotation {
        Annotation(
            type: .pin,
            coordinate: GeoCoordinate(latitude: lat, longitude: lon),
            title: title,
            body: "A test pin",
            metadata: ["color": "red"],
            projectID: projectID
        )
    }

    private func makeNote() -> Annotation {
        Annotation(
            type: .note,
            coordinate: GeoCoordinate(latitude: 48.8566, longitude: 2.3522),
            title: "Test Note",
            body: "A note body",
            projectID: projectID
        )
    }

    private func makeRoute() -> Annotation {
        Annotation(
            type: .route,
            coordinate: GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
            title: "Test Route",
            body: "A hiking trail",
            routeCoordinates: [
                GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
                GeoCoordinate(latitude: 37.7849, longitude: -122.4094),
                GeoCoordinate(latitude: 37.7949, longitude: -122.3994)
            ],
            projectID: projectID
        )
    }

    private func makePolygon() -> Annotation {
        Annotation(
            type: .polygon,
            coordinate: GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
            title: "Test Polygon",
            body: "A park boundary",
            polygonCoordinates: [
                GeoCoordinate(latitude: 37.77, longitude: -122.42),
                GeoCoordinate(latitude: 37.78, longitude: -122.42),
                GeoCoordinate(latitude: 37.78, longitude: -122.41),
                GeoCoordinate(latitude: 37.77, longitude: -122.41)
            ],
            projectID: projectID
        )
    }

    private func parseJSON(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    // MARK: - FeatureCollection Tests

    func testExportEmptyAnnotations() throws {
        let data = try exporter.export(annotations: [], projectName: "Empty")
        let json = try parseJSON(data)
        XCTAssertEqual(json["type"] as? String, "FeatureCollection")
        let features = json["features"] as? [[String: Any]]
        XCTAssertEqual(features?.count, 0)
    }

    func testExportSinglePin() throws {
        let pin = makePin()
        let data = try exporter.export(annotations: [pin], projectName: "Pins")
        let json = try parseJSON(data)

        let features = json["features"] as! [[String: Any]]
        XCTAssertEqual(features.count, 1)

        let feature = features[0]
        XCTAssertEqual(feature["type"] as? String, "Feature")
        XCTAssertEqual(feature["id"] as? String, pin.id.uuidString)

        let geometry = feature["geometry"] as! [String: Any]
        XCTAssertEqual(geometry["type"] as? String, "Point")

        let coords = geometry["coordinates"] as! [Double]
        XCTAssertEqual(coords[0], -122.4194, accuracy: 0.0000001) // longitude first
        XCTAssertEqual(coords[1], 37.7749, accuracy: 0.0000001)   // latitude second
    }

    func testExportNoteAsPoint() throws {
        let note = makeNote()
        let data = try exporter.export(annotations: [note], projectName: "Notes")
        let json = try parseJSON(data)

        let features = json["features"] as! [[String: Any]]
        let geometry = features[0]["geometry"] as! [String: Any]
        XCTAssertEqual(geometry["type"] as? String, "Point")
    }

    func testExportRouteAsLineString() throws {
        let route = makeRoute()
        let data = try exporter.export(annotations: [route], projectName: "Routes")
        let json = try parseJSON(data)

        let features = json["features"] as! [[String: Any]]
        let geometry = features[0]["geometry"] as! [String: Any]
        XCTAssertEqual(geometry["type"] as? String, "LineString")

        let coords = geometry["coordinates"] as! [[Double]]
        XCTAssertEqual(coords.count, 3)
    }

    func testExportPolygonClosesRing() throws {
        let polygon = makePolygon()
        let data = try exporter.export(annotations: [polygon], projectName: "Polygons")
        let json = try parseJSON(data)

        let features = json["features"] as! [[String: Any]]
        let geometry = features[0]["geometry"] as! [String: Any]
        XCTAssertEqual(geometry["type"] as? String, "Polygon")

        let rings = geometry["coordinates"] as! [[[Double]]]
        let ring = rings[0]
        // Ring must be closed: first == last
        XCTAssertEqual(ring.first, ring.last)
        XCTAssertEqual(ring.count, 5) // 4 points + closing point
    }

    func testExportProperties() throws {
        let pin = makePin()
        let data = try exporter.export(annotations: [pin], projectName: "Props")
        let json = try parseJSON(data)

        let features = json["features"] as! [[String: Any]]
        let props = features[0]["properties"] as! [String: Any]

        XCTAssertEqual(props["title"] as? String, "Test Pin")
        XCTAssertEqual(props["body"] as? String, "A test pin")
        XCTAssertEqual(props["annotationType"] as? String, "pin")
        XCTAssertNotNil(props["createdAt"])
        XCTAssertNotNil(props["updatedAt"])

        let meta = props["metadata"] as? [String: String]
        XCTAssertEqual(meta?["color"], "red")
    }

    func testExportAllAnnotationTypes() throws {
        let annotations = [makePin(), makeNote(), makeRoute(), makePolygon()]
        let data = try exporter.export(annotations: annotations, projectName: "Mixed")
        let json = try parseJSON(data)

        let features = json["features"] as! [[String: Any]]
        XCTAssertEqual(features.count, 4)

        let types = features.map { ($0["geometry"] as! [String: Any])["type"] as! String }
        XCTAssertTrue(types.contains("Point"))
        XCTAssertTrue(types.contains("LineString"))
        XCTAssertTrue(types.contains("Polygon"))
    }

    func testRoundTripJSON() throws {
        let pin = makePin()
        let data = try exporter.export(annotations: [pin], projectName: "RoundTrip")
        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data)
        let reEncoded = try JSONSerialization.data(withJSONObject: json)
        XCTAssertFalse(reEncoded.isEmpty)
    }
}

// MARK: - KML Exporter Tests

final class KMLExporterTests: XCTestCase {

    let exporter = KMLExporter()
    let projectID = UUID()

    // MARK: - Helpers

    private func makePin(title: String = "Test Pin") -> Annotation {
        Annotation(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
            title: title,
            body: "A test pin",
            projectID: projectID
        )
    }

    private func makeRoute() -> Annotation {
        Annotation(
            type: .route,
            coordinate: GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
            title: "Test Route",
            body: "A hiking trail",
            routeCoordinates: [
                GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
                GeoCoordinate(latitude: 37.7849, longitude: -122.4094),
                GeoCoordinate(latitude: 37.7949, longitude: -122.3994)
            ],
            projectID: projectID
        )
    }

    private func makePolygon() -> Annotation {
        Annotation(
            type: .polygon,
            coordinate: GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
            title: "Test Polygon",
            body: "A park boundary",
            polygonCoordinates: [
                GeoCoordinate(latitude: 37.77, longitude: -122.42),
                GeoCoordinate(latitude: 37.78, longitude: -122.42),
                GeoCoordinate(latitude: 37.78, longitude: -122.41),
                GeoCoordinate(latitude: 37.77, longitude: -122.41)
            ],
            projectID: projectID
        )
    }

    private func makeNote() -> Annotation {
        Annotation(
            type: .note,
            coordinate: GeoCoordinate(latitude: 48.8566, longitude: 2.3522),
            title: "Test Note",
            body: "A note body",
            projectID: projectID
        )
    }

    private func xmlString(_ data: Data) -> String {
        String(data: data, encoding: .utf8)!
    }

    // MARK: - Structure Tests

    func testExportProducesValidKMLStructure() throws {
        let data = try exporter.export(annotations: [makePin()], projectName: "Test")
        let kml = xmlString(data)

        XCTAssertTrue(kml.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(kml.contains("<kml xmlns=\"http://www.opengis.net/kml/2.2\">"))
        XCTAssertTrue(kml.contains("<Document>"))
        XCTAssertTrue(kml.contains("</Document>"))
        XCTAssertTrue(kml.contains("</kml>"))
    }

    func testExportProjectName() throws {
        let data = try exporter.export(annotations: [], projectName: "My Project")
        let kml = xmlString(data)
        XCTAssertTrue(kml.contains("<name>My Project</name>"))
    }

    func testExportStyleDefinitions() throws {
        let data = try exporter.export(annotations: [], projectName: "Styles")
        let kml = xmlString(data)

        XCTAssertTrue(kml.contains("style-pin"))
        XCTAssertTrue(kml.contains("style-note"))
        XCTAssertTrue(kml.contains("style-route"))
        XCTAssertTrue(kml.contains("style-polygon"))
    }

    func testExportPinAsPoint() throws {
        let data = try exporter.export(annotations: [makePin()], projectName: "Pins")
        let kml = xmlString(data)

        XCTAssertTrue(kml.contains("<Point>"))
        XCTAssertTrue(kml.contains("-122.4194,37.7749,0"))
        XCTAssertTrue(kml.contains("<styleUrl>#style-pin</styleUrl>"))
    }

    func testExportNoteAsPoint() throws {
        let data = try exporter.export(annotations: [makeNote()], projectName: "Notes")
        let kml = xmlString(data)

        XCTAssertTrue(kml.contains("<Point>"))
        XCTAssertTrue(kml.contains("<styleUrl>#style-note</styleUrl>"))
    }

    func testExportRouteAsLineString() throws {
        let data = try exporter.export(annotations: [makeRoute()], projectName: "Routes")
        let kml = xmlString(data)

        XCTAssertTrue(kml.contains("<LineString>"))
        XCTAssertTrue(kml.contains("<styleUrl>#style-route</styleUrl>"))
        // Verify coordinates are space-separated
        XCTAssertTrue(kml.contains("-122.4194,37.7749,0 -122.4094,37.7849,0 -122.3994,37.7949,0"))
    }

    func testExportPolygonClosesRing() throws {
        let data = try exporter.export(annotations: [makePolygon()], projectName: "Polygons")
        let kml = xmlString(data)

        XCTAssertTrue(kml.contains("<Polygon>"))
        XCTAssertTrue(kml.contains("<outerBoundaryIs>"))
        XCTAssertTrue(kml.contains("<LinearRing>"))
        XCTAssertTrue(kml.contains("<styleUrl>#style-polygon</styleUrl>"))

        // Verify ring is closed (first coord appears at end)
        let coordsRange = kml.range(of: "<LinearRing>\n<coordinates>")!
        let afterCoords = kml[coordsRange.upperBound...]
        let endRange = afterCoords.range(of: "</coordinates>")!
        let coordString = String(afterCoords[..<endRange.lowerBound])
        let points = coordString.split(separator: " ")
        XCTAssertEqual(points.first, points.last)
    }

    func testExportExtendedData() throws {
        let pin = Annotation(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
            title: "Pin",
            body: "",
            metadata: ["color": "blue", "icon": "star"],
            projectID: projectID
        )
        let data = try exporter.export(annotations: [pin], projectName: "Meta")
        let kml = xmlString(data)

        XCTAssertTrue(kml.contains("<ExtendedData>"))
        XCTAssertTrue(kml.contains("annotationType"))
        XCTAssertTrue(kml.contains("meta-color"))
        XCTAssertTrue(kml.contains("meta-icon"))
    }

    func testExportXMLEscaping() throws {
        let pin = Annotation(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 0, longitude: 0),
            title: "Title <with> & \"special\" chars",
            body: "Body's <content>",
            projectID: projectID
        )
        let data = try exporter.export(annotations: [pin], projectName: "Project & <Test>")
        let kml = xmlString(data)

        XCTAssertTrue(kml.contains("Project &amp; &lt;Test&gt;"))
        XCTAssertTrue(kml.contains("Title &lt;with&gt; &amp; &quot;special&quot; chars"))
        XCTAssertTrue(kml.contains("Body&apos;s &lt;content&gt;"))
    }

    func testExportAllAnnotationTypes() throws {
        let annotations = [makePin(), makeNote(), makeRoute(), makePolygon()]
        let data = try exporter.export(annotations: annotations, projectName: "All")
        let kml = xmlString(data)

        XCTAssertTrue(kml.contains("<Point>"))
        XCTAssertTrue(kml.contains("<LineString>"))
        XCTAssertTrue(kml.contains("<Polygon>"))
        // 4 placemarks
        let placemarkCount = kml.components(separatedBy: "<Placemark").count - 1
        XCTAssertEqual(placemarkCount, 4)
    }

    func testExportUTF8Encoding() throws {
        let data = try exporter.export(annotations: [makePin()], projectName: "Test")
        XCTAssertNotNil(String(data: data, encoding: .utf8))
    }
}
