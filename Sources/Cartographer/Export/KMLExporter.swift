// MARK: - KML Exporter
// Exports annotations to KML format for Google Earth compatibility.

import Foundation

/// Exports Cartographer annotations to KML format.
public struct KMLExporter: Sendable {

    public init() {}

    /// Export annotations as a KML document.
    public func export(annotations: [Annotation], projectName: String) throws -> Data {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document>
        <name>\(escapeXML(projectName))</name>
        \(styleDefinitions())
        """

        for annotation in annotations {
            xml += placemark(from: annotation)
        }

        xml += """

        </Document>
        </kml>
        """

        guard let data = xml.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    // MARK: - Private

    private func styleDefinitions() -> String {
        """
        <Style id="style-pin">
        <IconStyle><color>ff0000ff</color><scale>1.0</scale></IconStyle>
        </Style>
        <Style id="style-note">
        <IconStyle><color>ff00ff00</color><scale>0.8</scale></IconStyle>
        </Style>
        <Style id="style-route">
        <LineStyle><color>ffff0000</color><width>3</width></LineStyle>
        </Style>
        <Style id="style-polygon">
        <LineStyle><color>ff0000ff</color><width>2</width></LineStyle>
        <PolyStyle><color>800000ff</color></PolyStyle>
        </Style>
        """
    }

    private func placemark(from annotation: Annotation) -> String {
        let styleUrl = "#style-\(annotation.type.rawValue)"
        var pm = """

        <Placemark id="\(annotation.id.uuidString)">
        <name>\(escapeXML(annotation.title))</name>
        <description>\(escapeXML(annotation.body))</description>
        <styleUrl>\(styleUrl)</styleUrl>
        \(geometryKML(from: annotation))
        <ExtendedData>
        <Data name="annotationType"><value>\(annotation.type.rawValue)</value></Data>
        <Data name="createdAt"><value>\(iso8601String(annotation.createdAt))</value></Data>
        <Data name="updatedAt"><value>\(iso8601String(annotation.updatedAt))</value></Data>
        <Data name="projectID"><value>\(annotation.projectID.uuidString)</value></Data>
        """

        for (key, value) in annotation.metadata.sorted(by: { $0.key < $1.key }) {
            pm += "\n<Data name=\"meta-\(escapeXML(key))\"><value>\(escapeXML(value))</value></Data>"
        }

        pm += """

        </ExtendedData>
        </Placemark>
        """
        return pm
    }

    private func geometryKML(from annotation: Annotation) -> String {
        switch annotation.type {
        case .pin, .note:
            return """
            <Point>
            <coordinates>\(kmlCoord(annotation.coordinate))</coordinates>
            </Point>
            """
        case .route:
            let coords = annotation.routeCoordinates ?? [annotation.coordinate]
            let coordString = coords.map { kmlCoord($0) }.joined(separator: " ")
            return """
            <LineString>
            <coordinates>\(coordString)</coordinates>
            </LineString>
            """
        case .polygon:
            let coords = annotation.polygonCoordinates ?? [annotation.coordinate]
            var ring = coords
            // KML polygons require closed rings
            if let first = ring.first, let last = ring.last,
               first.latitude != last.latitude || first.longitude != last.longitude {
                ring.append(first)
            }
            let coordString = ring.map { kmlCoord($0) }.joined(separator: " ")
            return """
            <Polygon>
            <outerBoundaryIs>
            <LinearRing>
            <coordinates>\(coordString)</coordinates>
            </LinearRing>
            </outerBoundaryIs>
            </Polygon>
            """
        }
    }

    /// KML coordinates: longitude,latitude,altitude (altitude defaults to 0).
    private func kmlCoord(_ coord: GeoCoordinate) -> String {
        let lon = roundTo7(coord.longitude)
        let lat = roundTo7(coord.latitude)
        return "\(lon),\(lat),0"
    }

    private func roundTo7(_ value: Double) -> Double {
        (value * 10_000_000).rounded() / 10_000_000
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

// MARK: - Export Error

public enum ExportError: Error, Sendable {
    case encodingFailed
}
