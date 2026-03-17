// MARK: - Annotation Engine
// Manages annotation CRUD through the CRDT operation log.
// Every mutation goes through the operation log — never write directly to SQLite.

import Foundation

/// Coordinates annotation creation, editing, and deletion through CRDTs.
public actor AnnotationEngine {
    private let clock: HLCClock
    private let operationLog: OperationLog
    private var spatialIndex: RTree<EntityID>
    /// In-memory cache of current annotation state, keyed by entity ID.
    private var annotations: [EntityID: Annotation] = [:]

    public init(clock: HLCClock, operationLog: OperationLog) {
        self.clock = clock
        self.operationLog = operationLog
        self.spatialIndex = RTree<EntityID>(maxEntries: 16)
    }

    /// Create a new annotation. Generates an insert operation and appends to the log.
    public func create(
        type: AnnotationType,
        coordinate: GeoCoordinate,
        title: String = "",
        body: String = "",
        projectID: EntityID
    ) async throws -> Annotation {
        let timestamp = await clock.tick()
        let annotationID = EntityID()
        let now = Date()

        let annotation = Annotation(
            id: annotationID,
            type: type,
            coordinate: coordinate,
            title: title,
            body: body,
            metadata: [:],
            createdAt: now,
            updatedAt: now,
            projectID: projectID
        )

        let payload = try JSONEncoder().encode(annotation)
        let operation = Operation(
            type: .insert,
            entityType: .annotation,
            entityID: annotationID,
            projectID: projectID,
            hlc: timestamp,
            payload: payload
        )

        try await operationLog.append(operation)

        // Update in-memory state and spatial index
        annotations[annotationID] = annotation
        spatialIndex.insert(RTreeEntry(element: annotationID, boundingBox: annotation.boundingBox))

        return annotation
    }

    /// Update an annotation field. Generates an update operation with changed fields only.
    public func update(
        annotationID: EntityID,
        title: String? = nil,
        body: String? = nil,
        coordinate: GeoCoordinate? = nil
    ) async throws {
        guard var annotation = annotations[annotationID] else { return }

        let timestamp = await clock.tick()

        let fieldUpdate = AnnotationFieldUpdate(
            coordinate: coordinate,
            title: title,
            body: body
        )

        let payload = try JSONEncoder().encode(fieldUpdate)
        let operation = Operation(
            type: .update,
            entityType: .annotation,
            entityID: annotationID,
            projectID: annotation.projectID,
            hlc: timestamp,
            payload: payload
        )

        try await operationLog.append(operation)

        // Apply changes to in-memory state
        if let title { annotation.title = title }
        if let body { annotation.body = body }
        if let coordinate {
            let oldBox = annotation.boundingBox
            annotation.coordinate = coordinate
            // Update R-tree: remove old entry, insert new
            _ = spatialIndex.remove(annotationID)
            spatialIndex.insert(RTreeEntry(element: annotationID, boundingBox: annotation.boundingBox))
        }
        annotation.updatedAt = Date()
        annotations[annotationID] = annotation
    }

    /// Delete an annotation. Generates a delete operation.
    public func delete(annotationID: EntityID, projectID: EntityID) async throws {
        let timestamp = await clock.tick()

        let payload = Data() // Delete operations carry no field data
        let operation = Operation(
            type: .delete,
            entityType: .annotation,
            entityID: annotationID,
            projectID: projectID,
            hlc: timestamp,
            payload: payload
        )

        try await operationLog.append(operation)

        // Remove from in-memory state and spatial index
        annotations.removeValue(forKey: annotationID)
        _ = spatialIndex.remove(annotationID)
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
        self.annotations = Dictionary(uniqueKeysWithValues: annotations.map { ($0.id, $0) })
        let entries = annotations.map { annotation in
            RTreeEntry(element: annotation.id, boundingBox: annotation.boundingBox)
        }
        spatialIndex = RTree.bulkLoad(entries, maxEntries: 16)
    }
}
