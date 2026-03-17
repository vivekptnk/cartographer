// MARK: - Core Types
// These are the foundational types used across all modules.
// They must remain value types and Sendable.

import Foundation
import CoreLocation

// MARK: - Identifiers

/// Unique identifier for annotations, projects, and operations.
public typealias EntityID = UUID

// MARK: - Coordinates & Geometry

/// A geographic coordinate with 7-decimal-place precision (±11mm).
public struct GeoCoordinate: Sendable, Codable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Axis-aligned bounding box for spatial queries.
public struct BoundingBox: Sendable, Codable, Hashable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    /// Returns true if this box intersects another.
    public func intersects(_ other: BoundingBox) -> Bool {
        !(other.minLatitude > maxLatitude ||
          other.maxLatitude < minLatitude ||
          other.minLongitude > maxLongitude ||
          other.maxLongitude < minLongitude)
    }

    /// Returns true if this box contains a point.
    public func contains(_ point: GeoCoordinate) -> Bool {
        point.latitude >= minLatitude && point.latitude <= maxLatitude &&
        point.longitude >= minLongitude && point.longitude <= maxLongitude
    }

    /// Returns the area of this bounding box (approximate, in degree²).
    public var area: Double {
        (maxLatitude - minLatitude) * (maxLongitude - minLongitude)
    }

    /// Returns the union of two bounding boxes.
    public func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(
            minLatitude: min(minLatitude, other.minLatitude),
            maxLatitude: max(maxLatitude, other.maxLatitude),
            minLongitude: min(minLongitude, other.minLongitude),
            maxLongitude: max(maxLongitude, other.maxLongitude)
        )
    }
}

// MARK: - Tile Coordinates

/// Slippy map tile coordinate (z/x/y).
public struct TileCoordinate: Sendable, Codable, Hashable {
    public let z: Int  // zoom level (0-19)
    public let x: Int  // column
    public let y: Int  // row

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }

    /// Number of tiles at this zoom level (per axis).
    public var tilesPerAxis: Int { 1 << z }

    /// Convert a geographic coordinate to a tile coordinate at a given zoom.
    public static func from(coordinate: GeoCoordinate, zoom: Int) -> TileCoordinate {
        let n = Double(1 << zoom)
        let x = Int((coordinate.longitude + 180.0) / 360.0 * n)
        let latRad = coordinate.latitude * .pi / 180.0
        let y = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)
        return TileCoordinate(z: zoom, x: x, y: y)
    }

    /// Bounding box of this tile in geographic coordinates.
    public var boundingBox: BoundingBox {
        let n = Double(tilesPerAxis)
        let lonMin = Double(x) / n * 360.0 - 180.0
        let lonMax = Double(x + 1) / n * 360.0 - 180.0
        let latMaxRad = atan(sinh(.pi * (1 - 2 * Double(y) / n)))
        let latMinRad = atan(sinh(.pi * (1 - 2 * Double(y + 1) / n)))
        return BoundingBox(
            minLatitude: latMinRad * 180.0 / .pi,
            maxLatitude: latMaxRad * 180.0 / .pi,
            minLongitude: lonMin,
            maxLongitude: lonMax
        )
    }
}

// MARK: - Annotation Types

/// The kind of annotation a user can place on the map.
public enum AnnotationType: String, Sendable, Codable, CaseIterable {
    case pin
    case route
    case polygon
    case note
}

/// A map annotation with all metadata.
public struct Annotation: Sendable, Codable, Identifiable, Hashable {
    public let id: EntityID
    public var type: AnnotationType
    public var coordinate: GeoCoordinate
    public var title: String
    public var body: String
    public var routeCoordinates: [GeoCoordinate]?   // for .route
    public var polygonCoordinates: [GeoCoordinate]?  // for .polygon
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
    public var projectID: EntityID

    public init(
        id: EntityID = EntityID(),
        type: AnnotationType,
        coordinate: GeoCoordinate,
        title: String = "",
        body: String = "",
        routeCoordinates: [GeoCoordinate]? = nil,
        polygonCoordinates: [GeoCoordinate]? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        projectID: EntityID
    ) {
        self.id = id
        self.type = type
        self.coordinate = coordinate
        self.title = title
        self.body = body
        self.routeCoordinates = routeCoordinates
        self.polygonCoordinates = polygonCoordinates
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.projectID = projectID
    }

    /// Bounding box for spatial indexing. Point for pins/notes, enclosing for routes/polygons.
    public var boundingBox: BoundingBox {
        switch type {
        case .pin, .note:
            return BoundingBox(
                minLatitude: coordinate.latitude,
                maxLatitude: coordinate.latitude,
                minLongitude: coordinate.longitude,
                maxLongitude: coordinate.longitude
            )
        case .route:
            guard let coords = routeCoordinates, !coords.isEmpty else {
                return BoundingBox(minLatitude: coordinate.latitude, maxLatitude: coordinate.latitude,
                                   minLongitude: coordinate.longitude, maxLongitude: coordinate.longitude)
            }
            return Self.enclosingBox(coords)
        case .polygon:
            guard let coords = polygonCoordinates, !coords.isEmpty else {
                return BoundingBox(minLatitude: coordinate.latitude, maxLatitude: coordinate.latitude,
                                   minLongitude: coordinate.longitude, maxLongitude: coordinate.longitude)
            }
            return Self.enclosingBox(coords)
        }
    }

    private static func enclosingBox(_ coords: [GeoCoordinate]) -> BoundingBox {
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        return BoundingBox(minLatitude: minLat, maxLatitude: maxLat, minLongitude: minLon, maxLongitude: maxLon)
    }
}

// MARK: - Operation Types

/// The kind of mutation recorded in the operation log.
public enum OperationType: String, Sendable, Codable {
    case insert
    case update
    case delete
}

/// The entity type an operation targets.
public enum EntityType: String, Sendable, Codable {
    case annotation
    case project
}

// MARK: - Errors

public enum TileError: Error, Sendable {
    case cacheMiss(TileCoordinate)
    case networkUnavailable
    case invalidTileData
    case cacheCorrupted
}

public enum CRDTError: Error, Sendable {
    case clockDrift(expected: UInt64, actual: UInt64)
    case invalidOperation(String)
    case mergeConflict(String)
}

public enum SyncError: Error, Sendable {
    case networkUnavailable
    case authenticationFailed
    case quotaExceeded
    case zoneNotFound(String)
    case serverError(String)
}

public enum DatabaseError: Error, Sendable {
    case connectionFailed(String)
    case queryFailed(String)
    case migrationFailed(version: Int, reason: String)
    case prepareStatementFailed(String)
}

// MARK: - Protocols

/// Anything that can provide tiles by URL.
public protocol TileSource: Sendable {
    func tileURL(for coordinate: TileCoordinate) -> URL
    var attribution: String { get }
    var maxZoom: Int { get }
}

/// Abstraction over sync transport (CloudKit, custom server, etc).
public protocol SyncTransport: Sendable {
    func push(operations: [Operation]) async throws
    func pull(since token: SyncToken?) async throws -> ([Operation], SyncToken)
}

/// Opaque sync cursor.
public struct SyncToken: Sendable, Codable {
    public let data: Data
    public init(data: Data) { self.data = data }
}
