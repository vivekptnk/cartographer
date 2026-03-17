// MARK: - KML Exporter
// Exports annotations to KML format for Google Earth compatibility.

import Foundation

/// Exports Cartographer annotations to KML format.
public struct KMLExporter: Sendable {

    public init() {}

    /// Export annotations as a KML document.
    public func export(annotations: [Annotation], projectName: String) throws -> Data {
        // TODO: Implement for CG-012
        // 1. Build KML XML document with styles for each annotation type
        // 2. Map each annotation to a KML Placemark
        //    - .pin/.note → Point
        //    - .route → LineString
        //    - .polygon → Polygon
        // 3. Serialize to UTF-8 XML
        fatalError("Not yet implemented — implement for CG-012")
    }
}
