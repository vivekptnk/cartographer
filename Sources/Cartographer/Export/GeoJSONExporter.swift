// MARK: - GeoJSON Exporter
// Exports annotations to GeoJSON FeatureCollection (RFC 7946).

import Foundation

/// Exports Cartographer annotations to GeoJSON format.
public struct GeoJSONExporter: Sendable {

    public init() {}

    /// Export annotations as a GeoJSON FeatureCollection.
    /// Validates against RFC 7946.
    public func export(annotations: [Annotation], projectName: String) throws -> Data {
        let features = annotations.map { feature(from: $0) }
        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]
        return try JSONSerialization.data(
            withJSONObject: collection,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    // MARK: - Private

    private func feature(from annotation: Annotation) -> [String: Any] {
        var feature: [String: Any] = [
            "type": "Feature",
            "geometry": geometry(from: annotation),
            "properties": properties(from: annotation)
        ]
        feature["id"] = annotation.id.uuidString
        return feature
    }

    private func geometry(from annotation: Annotation) -> [String: Any] {
        switch annotation.type {
        case .pin, .note:
            return [
                "type": "Point",
                "coordinates": coordinateArray(annotation.coordinate)
            ]
        case .route:
            let coords = annotation.routeCoordinates ?? [annotation.coordinate]
            return [
                "type": "LineString",
                "coordinates": coords.map { coordinateArray($0) }
            ]
        case .polygon:
            let coords = annotation.polygonCoordinates ?? [annotation.coordinate]
            // GeoJSON polygons require a linear ring (first == last)
            var ring = coords.map { coordinateArray($0) }
            if let first = ring.first, let last = ring.last,
               !coordinatesEqual(first, last) {
                ring.append(first)
            }
            return [
                "type": "Polygon",
                "coordinates": [ring]
            ]
        }
    }

    private func properties(from annotation: Annotation) -> [String: Any] {
        let iso8601 = ISO8601DateFormatter()
        var props: [String: Any] = [
            "title": annotation.title,
            "body": annotation.body,
            "annotationType": annotation.type.rawValue,
            "createdAt": iso8601.string(from: annotation.createdAt),
            "updatedAt": iso8601.string(from: annotation.updatedAt),
            "projectID": annotation.projectID.uuidString
        ]
        if !annotation.metadata.isEmpty {
            props["metadata"] = annotation.metadata
        }
        return props
    }

    /// RFC 7946: coordinates are [longitude, latitude].
    private func coordinateArray(_ coord: GeoCoordinate) -> [Double] {
        [
            roundTo7(coord.longitude),
            roundTo7(coord.latitude)
        ]
    }

    private func roundTo7(_ value: Double) -> Double {
        (value * 10_000_000).rounded() / 10_000_000
    }

    private func coordinatesEqual(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0 == $1 }
    }
}
