// MARK: - Map Coordinator
// @MainActor owner of an MKMapView's delegate, overlay registration, and
// annotation view reconciliation. Routes every user mutation through
// AnnotationEngine so operations land in the CRDT log — never mutates
// MKMapView annotations directly for user-initiated edits.

import Foundation
#if canImport(MapKit)
@preconcurrency import MapKit

/// Bridges SwiftUI / UIKit / AppKit gestures to the AnnotationEngine and owns
/// the visible-set reconciliation for an `MKMapView`.
///
/// Threading: pinned to `@MainActor` because `MKMapView` must only be touched
/// from the main thread. Actor-isolated engines are awaited explicitly.
@MainActor
public final class MapCoordinator: NSObject {

    // MARK: Dependencies

    public let annotationEngine: AnnotationEngine
    public let tileOverlay: CachingTileOverlay
    public let projectID: EntityID
    public var clusteringZoomThreshold: Int

    // MARK: Published state

    public private(set) var selectedAnnotationID: EntityID?
    public private(set) var visibleAnnotationIDs: Set<EntityID> = []
    public private(set) var currentClusters: [MapCluster] = []
    public private(set) var routeDraft: RouteDraft?

    // MARK: Callbacks (assign from the view layer)

    /// Invoked when the user selects a single annotation (either via tap on a
    /// pin or via expanding a single-member cluster). The SwiftUI layer uses
    /// this to present `AnnotationSheet`.
    public var onSelectAnnotation: (@MainActor (EntityID) -> Void)?

    /// Invoked when the user taps a multi-member cluster and the coordinator
    /// wants the map to zoom into the cluster's bounding box.
    public var onRequestZoom: (@MainActor (BoundingBox) -> Void)?

    // MARK: Attachment

    private weak var attachedMapView: MKMapView?

    public init(
        annotationEngine: AnnotationEngine,
        tileOverlay: CachingTileOverlay,
        projectID: EntityID,
        clusteringZoomThreshold: Int = 12
    ) {
        self.annotationEngine = annotationEngine
        self.tileOverlay = tileOverlay
        self.projectID = projectID
        self.clusteringZoomThreshold = clusteringZoomThreshold
    }

    /// Wire this coordinator up as the delegate of `mapView` and register the
    /// tile overlay. Idempotent.
    public func attach(to mapView: MKMapView) {
        self.attachedMapView = mapView
        mapView.delegate = self
        if !mapView.overlays.contains(where: { ($0 as AnyObject) === (tileOverlay as AnyObject) }) {
            mapView.addOverlay(tileOverlay, level: .aboveLabels)
        }
    }

    /// Release the `MKMapView`. Safe to call multiple times.
    public func detach() {
        if let mv = attachedMapView {
            if mv.delegate === self { mv.delegate = nil }
            mv.removeOverlay(tileOverlay)
        }
        attachedMapView = nil
    }

    // MARK: - Gesture intents
    //
    // These are the integration points the view layer drives. They are the
    // only public mutation paths — everything flows through
    // `AnnotationEngine` and therefore through the CRDT operation log.

    /// A background-area tap (i.e. a tap that did NOT hit an existing
    /// annotation view).
    ///
    /// - If a route draft is active, appends this waypoint.
    /// - Otherwise, creates a new pin at the coordinate.
    @discardableResult
    public func handleBackgroundTap(at coordinate: GeoCoordinate) async -> EntityID? {
        if routeDraft != nil {
            routeDraft?.coordinates.append(coordinate)
            return nil
        }
        do {
            let annotation = try await annotationEngine.create(
                type: .pin,
                coordinate: coordinate,
                projectID: projectID
            )
            await refreshVisibleSet()
            return annotation.id
        } catch {
            return nil
        }
    }

    /// MKMapView reports a tap on an existing annotation.
    public func handleAnnotationSelect(_ id: EntityID) {
        selectedAnnotationID = id
        onSelectAnnotation?(id)
    }

    /// MKMapView reports a tap on a cluster bubble.
    ///
    /// - Single-member cluster → select its member.
    /// - Multi-member cluster → request a zoom-in on its bounding box.
    public func handleClusterSelect(_ cluster: MapCluster) {
        if !cluster.isCluster, let id = cluster.memberIDs.first {
            handleAnnotationSelect(id)
            return
        }
        onRequestZoom?(cluster.boundingBox)
    }

    /// Begin a route-drafting session anchored at `coordinate`. Following
    /// taps append to the route; a double-tap ends it.
    public func handleLongPress(at coordinate: GeoCoordinate) {
        routeDraft = RouteDraft(coordinates: [coordinate])
    }

    /// Commit the current route draft as a `.route` annotation. No-op if
    /// no draft is active or the draft has fewer than two waypoints.
    @discardableResult
    public func handleDoubleTap(at coordinate: GeoCoordinate) async -> EntityID? {
        guard var draft = routeDraft else { return nil }
        draft.coordinates.append(coordinate)
        let waypoints = draft.coordinates
        routeDraft = nil
        guard waypoints.count >= 2 else { return nil }
        do {
            let annotation = try await annotationEngine.create(
                type: .route,
                coordinate: waypoints[0],
                projectID: projectID
            )
            await refreshVisibleSet()
            return annotation.id
        } catch {
            return nil
        }
    }

    /// Discard the in-progress route draft.
    public func cancelRouteDraft() {
        routeDraft = nil
    }

    /// Edit the selected (or any) annotation. Drives `AnnotationEngine.update`
    /// so the change is LWW-backed via the operation log.
    public func applyEdit(
        annotationID: EntityID,
        title: String? = nil,
        body: String? = nil,
        coordinate: GeoCoordinate? = nil
    ) async {
        try? await annotationEngine.update(
            annotationID: annotationID,
            title: title,
            body: body,
            coordinate: coordinate
        )
    }

    /// Delete the annotation via the operation log.
    public func deleteAnnotation(_ annotationID: EntityID) async {
        try? await annotationEngine.delete(
            annotationID: annotationID,
            projectID: projectID
        )
        visibleAnnotationIDs.remove(annotationID)
        currentClusters.removeAll { $0.memberIDs.contains(annotationID) }
        if selectedAnnotationID == annotationID {
            selectedAnnotationID = nil
        }
    }

    // MARK: - Visible-set reconciliation

    /// Recompute the visible set and clusters from the attached map view's
    /// current region, returning the diff against the previous set.
    @discardableResult
    public func refreshVisibleSet() async -> MapVisibleDiff {
        guard let mv = attachedMapView else {
            return MapVisibleDiff(previous: visibleAnnotationIDs, current: visibleAnnotationIDs)
        }
        return await refreshVisibleSet(
            region: mv.region,
            coordinateProvider: nil
        )
    }

    /// Pure version used by the harness and by the MapKit delegate hook.
    ///
    /// - Parameter coordinateProvider: optional map of ids to coordinates. If
    ///   provided, clustering uses this map instead of round-tripping through
    ///   `AnnotationEngine.materialize`. Callers that already have the
    ///   coordinates in hand (e.g. the SwiftUI state store) should pass them.
    @discardableResult
    public func refreshVisibleSet(
        region: MKCoordinateRegion,
        coordinateProvider: [EntityID: GeoCoordinate]?
    ) async -> MapVisibleDiff {
        let bbox = Self.boundingBox(for: region)
        let visibleIDs = await annotationEngine.annotations(in: bbox)
        let nextSet = Set(visibleIDs)
        let diff = MapVisibleDiff(previous: visibleAnnotationIDs, current: nextSet)
        visibleAnnotationIDs = nextSet

        let zoom = Self.zoom(for: region)
        let coordinates: [EntityID: GeoCoordinate] = coordinateProvider ?? [:]
        currentClusters = computeClusters(
            visibleIDs: visibleIDs,
            zoom: zoom,
            coordinates: coordinates
        )
        return diff
    }

    /// Produce clusters for the given visible ids at the given zoom.
    ///
    /// When `zoom >= clusteringZoomThreshold`, each id becomes its own
    /// degenerate cluster. Otherwise, grid-bucket via `MapClusterer`.
    public func computeClusters(
        visibleIDs: [EntityID],
        zoom: Int,
        coordinates: [EntityID: GeoCoordinate]
    ) -> [MapCluster] {
        let items: [(EntityID, GeoCoordinate)] = visibleIDs.compactMap { id in
            guard let coord = coordinates[id] else { return nil }
            return (id, coord)
        }
        guard zoom < clusteringZoomThreshold else {
            return items.map { id, coord in
                MapCluster(
                    id: id,
                    coordinate: coord,
                    boundingBox: BoundingBox(
                        minLatitude: coord.latitude,
                        maxLatitude: coord.latitude,
                        minLongitude: coord.longitude,
                        maxLongitude: coord.longitude
                    ),
                    memberIDs: [id]
                )
            }
        }
        let config = MapClusteringConfig.automatic(
            zoom: zoom,
            zoomThreshold: clusteringZoomThreshold
        )
        return MapClusterer.cluster(
            annotations: items,
            cellSizeDegrees: config.cellSizeDegrees
        )
    }

    // MARK: - Geometry helpers

    /// Convert an `MKCoordinateRegion` to a Cartographer `BoundingBox`.
    public nonisolated static func boundingBox(for region: MKCoordinateRegion) -> BoundingBox {
        let dLat = region.span.latitudeDelta / 2
        let dLon = region.span.longitudeDelta / 2
        return BoundingBox(
            minLatitude: region.center.latitude - dLat,
            maxLatitude: region.center.latitude + dLat,
            minLongitude: region.center.longitude - dLon,
            maxLongitude: region.center.longitude + dLon
        )
    }

    /// Approximate slippy-map zoom level for an `MKCoordinateRegion`.
    public nonisolated static func zoom(for region: MKCoordinateRegion) -> Int {
        let delta = max(region.span.longitudeDelta, 1e-7)
        let z = log2(360.0 / delta)
        return max(0, min(20, Int(z.rounded())))
    }
}

// MARK: - MKMapViewDelegate

extension MapCoordinator: MKMapViewDelegate {

    public nonisolated func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        // Hop to the main actor to read region / state safely.
        Task { @MainActor in
            await self.refreshVisibleSet()
        }
    }

    public nonisolated func mapView(
        _ mapView: MKMapView,
        rendererFor overlay: any MKOverlay
    ) -> MKOverlayRenderer {
        if let tile = overlay as? MKTileOverlay {
            return MKTileOverlayRenderer(tileOverlay: tile)
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

#endif
