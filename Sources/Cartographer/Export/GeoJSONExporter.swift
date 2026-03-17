// MARK: - GeoJSON Exporter
// Exports annotations to GeoJSON FeatureCollection (RFC 7946).

import Foundation

/// Exports Cartographer annotations to GeoJSON format.
public struct GeoJSONExporter: Sendable {

    public init() {}

    /// Export annotations as a GeoJSON FeatureCollection.
    /// Validates against RFC 7946.
    public func export(annotations: [Annotation], projectName: String) throws -> Data {
        // TODO: Implement for CG-012
        // 1. Map each annotation to a GeoJSON Feature
        //    - .pin/.note → Point geometry
        //    - .route → LineString geometry
        //    - .polygon → Polygon geometry
        // 2. Wrap in FeatureCollection
        // 3. Serialize to JSON with coordinate precision of 7 decimal places
        fatalError("Not yet implemented — implement for CG-012")
    }
}
