import SwiftUI
import MapKit
import Cartographer

/// Minimal map shell the demo uses until CHA-136's `MapCoordinator` lands.
///
/// TODO(CHA-136): replace this wrapper with `MapCoordinator`-backed
/// representable. The ticket defines clustering, viewport-driven R-tree
/// queries, and the long-press interaction. Until it merges, this view wires
/// the engine's published annotations directly onto `MKMapView` as point
/// annotations and forwards tap-to-add through a closure.
///
/// TODO(CHA-135): once `CachingTileOverlay` is public, swap the raw
/// `MKTileOverlay` constructed in `updateUIView` for the caching one. The
/// `AppContainer`'s `tileCache` is ready to back it.
struct DemoMapView: UIViewRepresentable {
    let annotations: [Cartographer.Annotation]
    let tileSource: any TileSource
    let onLongPress: (GeoCoordinate) -> Void
    @Binding var visibleRegion: MKCoordinateRegion

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.showsUserLocation = false

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        map.addGestureRecognizer(longPress)

        map.setRegion(visibleRegion, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.attach(map)

        // Swap in the current tile overlay if the source identity changed.
        let desiredURL = tileSource.tileURL(for: TileCoordinate(z: 0, x: 0, y: 0)).absoluteString
        if context.coordinator.installedTileAttribution != desiredURL {
            map.overlays
                .filter { $0 is MKTileOverlay }
                .forEach { map.removeOverlay($0) }
            let overlay = MKTileOverlay(
                urlTemplate: tileSource.tileURL(
                    for: TileCoordinate(z: 0, x: 0, y: 0)
                ).absoluteString
                    .replacingOccurrences(of: "/0/0/0", with: "/{z}/{x}/{y}")
            )
            overlay.canReplaceMapContent = true
            map.addOverlay(overlay, level: .aboveLabels)
            context.coordinator.installedTileAttribution = desiredURL
        }

        // Reconcile annotations against current engine state.
        let existingByID = Dictionary(
            uniqueKeysWithValues: map.annotations
                .compactMap { $0 as? DemoPointAnnotation }
                .map { ($0.entityID, $0) }
        )
        let incomingIDs = Set(annotations.map { $0.id })

        let toRemove = existingByID.filter { !incomingIDs.contains($0.key) }.values
        map.removeAnnotations(Array(toRemove))

        let toAdd = annotations.filter { existingByID[$0.id] == nil }
        map.addAnnotations(toAdd.map { DemoPointAnnotation(annotation: $0) })
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        let onLongPress: (GeoCoordinate) -> Void
        weak var map: MKMapView?
        var installedTileAttribution: String?

        init(onLongPress: @escaping (GeoCoordinate) -> Void) {
            self.onLongPress = onLongPress
        }

        func attach(_ map: MKMapView) { self.map = map }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map else { return }
            let point = gesture.location(in: map)
            let coord = map.convert(point, toCoordinateFrom: map)
            onLongPress(GeoCoordinate(latitude: coord.latitude, longitude: coord.longitude))
        }
    }
}

/// Internal MKAnnotation wrapper that keeps a reference to the CRDT-backed
/// annotation ID so the view can reconcile by identity.
final class DemoPointAnnotation: NSObject, MKAnnotation {
    let entityID: EntityID
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(annotation: Cartographer.Annotation) {
        self.entityID = annotation.id
        self.coordinate = annotation.coordinate.clLocationCoordinate
        self.title = annotation.title.isEmpty ? "Untitled" : annotation.title
        self.subtitle = annotation.body.isEmpty ? nil : annotation.body
    }
}
