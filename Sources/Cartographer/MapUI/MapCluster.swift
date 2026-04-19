// MARK: - Map Cluster Types
// Pure value types describing a cluster of annotations as surfaced to the
// rendering layer. Independent of MapKit so they can be tested without a map.

import Foundation

/// A group of annotations rendered as a single view on the map.
///
/// `memberIDs.count == 1` is a "degenerate" cluster — the representative is
/// a single pin rendered with its own view. `memberIDs.count > 1` is a true
/// cluster that shows a count badge and expands on tap.
public struct MapCluster: Sendable, Hashable, Identifiable {
    public let id: EntityID
    public let coordinate: GeoCoordinate
    public let boundingBox: BoundingBox
    public let memberIDs: [EntityID]

    public var count: Int { memberIDs.count }
    public var isCluster: Bool { memberIDs.count > 1 }

    public init(
        id: EntityID,
        coordinate: GeoCoordinate,
        boundingBox: BoundingBox,
        memberIDs: [EntityID]
    ) {
        self.id = id
        self.coordinate = coordinate
        self.boundingBox = boundingBox
        self.memberIDs = memberIDs
    }
}

/// Diff between two sets of visible annotation ids. Used by `MapCoordinator`
/// so MKMapView only add/removes the ids that actually changed frame-to-frame.
public struct MapVisibleDiff: Sendable, Equatable {
    public let added: Set<EntityID>
    public let removed: Set<EntityID>
    public let retained: Set<EntityID>

    public init(previous: Set<EntityID>, current: Set<EntityID>) {
        self.added = current.subtracting(previous)
        self.removed = previous.subtracting(current)
        self.retained = current.intersection(previous)
    }

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }
}

/// Configuration for annotation clustering.
///
/// `zoomThreshold` — clustering is active when the map's current zoom is
/// strictly less than this value. PRD CG-006 pins this at 12.
///
/// `cellSizeDegrees` — width/height of each grid cell used for bucketing, in
/// degrees. Callers usually derive this from the current zoom via
/// `automatic(zoom:)`.
public struct MapClusteringConfig: Sendable, Hashable {
    public let zoomThreshold: Int
    public let cellSizeDegrees: Double

    public init(zoomThreshold: Int = 12, cellSizeDegrees: Double) {
        precondition(cellSizeDegrees > 0, "cell size must be positive")
        self.zoomThreshold = zoomThreshold
        self.cellSizeDegrees = cellSizeDegrees
    }

    /// Cell size derived from zoom so that buckets stay visually stable across
    /// the zoom range: 4 cells per tile edge at the given zoom.
    public static func automatic(zoom: Int, zoomThreshold: Int = 12) -> MapClusteringConfig {
        let safe = max(zoom, 1)
        let cell = 360.0 / Double(1 << safe) / 4.0
        return MapClusteringConfig(zoomThreshold: zoomThreshold, cellSizeDegrees: cell)
    }
}

/// In-progress route being captured from user gestures (long-press start,
/// subsequent taps append waypoints, double-tap commits).
public struct RouteDraft: Sendable, Hashable {
    public var coordinates: [GeoCoordinate]

    public init(coordinates: [GeoCoordinate]) {
        self.coordinates = coordinates
    }
}
