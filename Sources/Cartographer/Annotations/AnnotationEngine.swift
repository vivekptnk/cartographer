// MARK: - Annotation Engine
// Manages annotation CRUD through the CRDT operation log.
// Every mutation goes through the operation log — never write directly to SQLite.

import Foundation

/// Coordinates annotation creation, editing, and deletion through CRDTs.
public actor AnnotationEngine {
    private let clock: HLCClock
    private var spatialIndex: RTree<EntityID>

    public init(clock: HLCClock) {
        self.clock = clock
        self.spatialIndex = RTree<EntityID>(maxEntries: 16)
    }

    /// Create a new annotation. Generates an insert operation and appends to the log.
    public func create(
        type: AnnotationType,
        coordinate: GeoCoordinate,
        title: String = "",
        body: String = "",
        projectID: EntityID
    ) async -> Annotation {
        // TODO: Implement for CG-006
        // 1. Generate HLC timestamp
        // 2. Create Annotation struct
        // 3. Create Operation(.insert, ...)
        // 4. Append to operation log
        // 5. Insert into R-tree
        // 6. Return annotation
        fatalError("Not yet implemented — implement for CG-006")
    }

    /// Update an annotation field. Generates an update operation.
    public func update(
        annotationID: EntityID,
        title: String? = nil,
        body: String? = nil,
        coordinate: GeoCoordinate? = nil
    ) async {
        // TODO: Implement for CG-006
        // 1. Generate HLC timestamp
        // 2. Create Operation(.update, ...) with changed fields only
        // 3. Append to operation log
        // 4. Update R-tree if coordinate changed
        fatalError("Not yet implemented — implement for CG-006")
    }

    /// Delete an annotation. Generates a delete operation.
    public func delete(annotationID: EntityID, projectID: EntityID) async {
        // TODO: Implement for CG-006
        fatalError("Not yet implemented — implement for CG-006")
    }

    /// Query annotations within a bounding box using the R-tree.
    /// Target: < 10ms for 10K annotations.
    public func annotations(in box: BoundingBox) -> [EntityID] {
        spatialIndex.search(in: box).map(\.element)
    }

    /// Find the nearest annotation to a point (for tap-to-select).
    public func nearest(to point: GeoCoordinate) -> EntityID? {
        spatialIndex.nearest(to: point)?.element
    }

    /// Rebuild the spatial index from all annotations (e.g., on app launch).
    public func rebuildIndex(from annotations: [Annotation]) {
        let entries = annotations.map { annotation in
            RTreeEntry(element: annotation.id, boundingBox: annotation.boundingBox)
        }
        spatialIndex = RTree.bulkLoad(entries, maxEntries: 16)
    }
}
