// MARK: - SwiftUI MapView Wrapper
// Thin `ViewRepresentable` that hosts an `MKMapView` driven by a
// `MapCoordinator`. Single-tap creates a pin / appends to a route, long-press
// starts a route, double-tap commits the route. Platform split: iOS uses
// `UIViewRepresentable` + `UIGestureRecognizer`; macOS uses
// `NSViewRepresentable` + `NSGestureRecognizer`.

import Foundation
#if canImport(SwiftUI) && canImport(MapKit)
import SwiftUI
@preconcurrency import MapKit

// MARK: iOS

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit

public struct MapView: UIViewRepresentable {
    @ObservedObject public var store: MapViewStore

    public init(store: MapViewStore) {
        self.store = store
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView(frame: .zero)
        mv.showsUserLocation = false
        store.coordinator.attach(to: mv)
        context.coordinator.install(on: mv, store: store)
        return mv
    }

    public func updateUIView(_ mv: MKMapView, context: Context) {
        if let region = store.region, !Self.regionsEqual(mv.region, region) {
            mv.setRegion(region, animated: true)
        }
    }

    public func makeCoordinator() -> GestureCoordinator {
        GestureCoordinator()
    }

    public static func dismantleUIView(_ mv: MKMapView, coordinator: GestureCoordinator) {
        coordinator.uninstall(from: mv)
    }

    private static func regionsEqual(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        abs(a.center.latitude  - b.center.latitude)  < 1e-6 &&
        abs(a.center.longitude - b.center.longitude) < 1e-6 &&
        abs(a.span.latitudeDelta  - b.span.latitudeDelta)  < 1e-6 &&
        abs(a.span.longitudeDelta - b.span.longitudeDelta) < 1e-6
    }

    @MainActor
    public final class GestureCoordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var mapView: MKMapView?
        private weak var store: MapViewStore?
        private var singleTap: UITapGestureRecognizer?
        private var doubleTap: UITapGestureRecognizer?
        private var longPress: UILongPressGestureRecognizer?

        func install(on mv: MKMapView, store: MapViewStore) {
            self.mapView = mv
            self.store = store

            let double = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            double.numberOfTapsRequired = 2
            double.delegate = self
            mv.addGestureRecognizer(double)
            self.doubleTap = double

            let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            single.numberOfTapsRequired = 1
            single.delegate = self
            single.require(toFail: double)
            mv.addGestureRecognizer(single)
            self.singleTap = single

            let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            press.minimumPressDuration = 0.5
            press.delegate = self
            mv.addGestureRecognizer(press)
            self.longPress = press
        }

        func uninstall(from mv: MKMapView) {
            for gr in [singleTap, doubleTap, longPress].compactMap({ $0 }) {
                mv.removeGestureRecognizer(gr)
            }
            singleTap = nil
            doubleTap = nil
            longPress = nil
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Let MKMapView's pan/pinch/etc. keep working.
            return true
        }

        @MainActor
        @objc private func handleSingleTap(_ gr: UITapGestureRecognizer) {
            guard let mv = mapView, let store = store, gr.state == .ended else { return }
            let pt = gr.location(in: mv)
            if let hit = hitTestAnnotation(at: pt, in: mv) {
                store.coordinator.handleAnnotationSelect(hit)
                return
            }
            let coord = mv.convert(pt, toCoordinateFrom: mv)
            let geo = GeoCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            let coordinator = store.coordinator
            Task { @MainActor in
                await coordinator.handleBackgroundTap(at: geo)
            }
        }

        @MainActor
        @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            guard let mv = mapView, let store = store, gr.state == .ended else { return }
            let pt = gr.location(in: mv)
            let coord = mv.convert(pt, toCoordinateFrom: mv)
            let geo = GeoCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            let coordinator = store.coordinator
            Task { @MainActor in
                await coordinator.handleDoubleTap(at: geo)
            }
        }

        @MainActor
        @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            guard let mv = mapView, let store = store, gr.state == .began else { return }
            let pt = gr.location(in: mv)
            let coord = mv.convert(pt, toCoordinateFrom: mv)
            let geo = GeoCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            store.coordinator.handleLongPress(at: geo)
        }

        @MainActor
        private func hitTestAnnotation(at point: CGPoint, in mv: MKMapView) -> EntityID? {
            for annotation in mv.annotations {
                guard let view = mv.view(for: annotation) else { continue }
                let rect = view.convert(view.bounds, to: mv)
                if rect.contains(point), let ided = annotation as? MapAnnotation {
                    return ided.entityID
                }
            }
            return nil
        }
    }
}
#endif

// MARK: macOS

#if os(macOS)
import AppKit

public struct MapView: NSViewRepresentable {
    @ObservedObject public var store: MapViewStore

    public init(store: MapViewStore) {
        self.store = store
    }

    public func makeNSView(context: Context) -> MKMapView {
        let mv = MKMapView(frame: .zero)
        store.coordinator.attach(to: mv)
        context.coordinator.install(on: mv, store: store)
        return mv
    }

    public func updateNSView(_ mv: MKMapView, context: Context) {
        if let region = store.region, !Self.regionsEqual(mv.region, region) {
            mv.setRegion(region, animated: true)
        }
    }

    public func makeCoordinator() -> GestureCoordinator {
        GestureCoordinator()
    }

    public static func dismantleNSView(_ mv: MKMapView, coordinator: GestureCoordinator) {
        coordinator.uninstall(from: mv)
    }

    private static func regionsEqual(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        abs(a.center.latitude  - b.center.latitude)  < 1e-6 &&
        abs(a.center.longitude - b.center.longitude) < 1e-6 &&
        abs(a.span.latitudeDelta  - b.span.latitudeDelta)  < 1e-6 &&
        abs(a.span.longitudeDelta - b.span.longitudeDelta) < 1e-6
    }

    @MainActor
    public final class GestureCoordinator: NSObject, NSGestureRecognizerDelegate {
        private weak var mapView: MKMapView?
        private weak var store: MapViewStore?
        private var click: NSClickGestureRecognizer?
        private var doubleClick: NSClickGestureRecognizer?
        private var longPress: NSPressGestureRecognizer?

        func install(on mv: MKMapView, store: MapViewStore) {
            self.mapView = mv
            self.store = store

            let double = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
            double.numberOfClicksRequired = 2
            double.delegate = self
            mv.addGestureRecognizer(double)
            self.doubleClick = double

            let single = NSClickGestureRecognizer(target: self, action: #selector(handleSingleClick(_:)))
            single.numberOfClicksRequired = 1
            single.delegate = self
            mv.addGestureRecognizer(single)
            self.click = single

            let press = NSPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            press.minimumPressDuration = 0.5
            press.delegate = self
            mv.addGestureRecognizer(press)
            self.longPress = press
        }

        func uninstall(from mv: MKMapView) {
            for gr in [click, doubleClick, longPress].compactMap({ $0 as NSGestureRecognizer? }) {
                mv.removeGestureRecognizer(gr)
            }
            click = nil
            doubleClick = nil
            longPress = nil
        }

        @MainActor
        @objc private func handleSingleClick(_ gr: NSClickGestureRecognizer) {
            guard let mv = mapView, let store = store, gr.state == .ended else { return }
            let pt = gr.location(in: mv)
            let coord = mv.convert(pt, toCoordinateFrom: mv)
            let geo = GeoCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            let coordinator = store.coordinator
            Task { @MainActor in
                await coordinator.handleBackgroundTap(at: geo)
            }
        }

        @MainActor
        @objc private func handleDoubleClick(_ gr: NSClickGestureRecognizer) {
            guard let mv = mapView, let store = store, gr.state == .ended else { return }
            let pt = gr.location(in: mv)
            let coord = mv.convert(pt, toCoordinateFrom: mv)
            let geo = GeoCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            let coordinator = store.coordinator
            Task { @MainActor in
                await coordinator.handleDoubleTap(at: geo)
            }
        }

        @MainActor
        @objc private func handleLongPress(_ gr: NSPressGestureRecognizer) {
            guard let mv = mapView, let store = store, gr.state == .began else { return }
            let pt = gr.location(in: mv)
            let coord = mv.convert(pt, toCoordinateFrom: mv)
            let geo = GeoCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            store.coordinator.handleLongPress(at: geo)
        }
    }
}
#endif

// MARK: Store + Annotation bridge

/// Observable store bridging the `MapCoordinator` to SwiftUI. Holds the
/// coordinator, the currently-bound map region, and (optionally) a selected
/// annotation id for sheet presentation.
@MainActor
public final class MapViewStore: ObservableObject {
    public let coordinator: MapCoordinator
    @Published public var region: MKCoordinateRegion?
    @Published public var presentedAnnotationID: EntityID?

    public init(
        coordinator: MapCoordinator,
        initialRegion: MKCoordinateRegion? = nil
    ) {
        self.coordinator = coordinator
        self.region = initialRegion
        coordinator.onSelectAnnotation = { [weak self] id in
            self?.presentedAnnotationID = id
        }
        coordinator.onRequestZoom = { [weak self] bbox in
            self?.zoom(to: bbox)
        }
    }

    public func zoom(to bbox: BoundingBox) {
        let center = CLLocationCoordinate2D(
            latitude:  (bbox.minLatitude  + bbox.maxLatitude)  / 2,
            longitude: (bbox.minLongitude + bbox.maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max((bbox.maxLatitude  - bbox.minLatitude)  * 1.5, 0.001),
            longitudeDelta: max((bbox.maxLongitude - bbox.minLongitude) * 1.5, 0.001)
        )
        self.region = MKCoordinateRegion(center: center, span: span)
    }
}

/// MKAnnotation wrapper that carries the Cartographer `EntityID` so the
/// gesture layer can hit-test pins back to their id.
public final class MapAnnotation: NSObject, MKAnnotation {
    public let entityID: EntityID
    public dynamic var coordinate: CLLocationCoordinate2D
    public var title: String?
    public var subtitle: String?

    public init(
        entityID: EntityID,
        coordinate: CLLocationCoordinate2D,
        title: String? = nil,
        subtitle: String? = nil
    ) {
        self.entityID = entityID
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
    }
}

#endif
