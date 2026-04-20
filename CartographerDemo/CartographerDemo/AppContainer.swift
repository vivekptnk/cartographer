import Foundation
import SwiftUI
import Cartographer

/// Single source of truth for every engine component the demo exercises.
///
/// The container is deliberately a plain `@MainActor` `ObservableObject` (not
/// an actor) so SwiftUI bindings are cheap. Every call that touches engine
/// state hops into the underlying actor (`AnnotationEngine`, `OperationLog`,
/// `SyncEngine`, `TileCache`, `HLCClock`) via `await`.
@MainActor
final class AppContainer: ObservableObject {

    // MARK: - Published UI state

    @Published var annotations: [Cartographer.Annotation] = []
    @Published var selectedTileSource: TileSourceChoice = .openStreetMap
    @Published var syncEnabled: Bool = false
    @Published var syncStatus: String = "disabled"
    @Published var regionDownloadProgress: Double = 0.0
    @Published var lastActionMessage: String?

    // MARK: - Engine

    // The sole demo project: one project, one node, no user accounts required.
    let projectID: EntityID = EntityID()
    let nodeID: UUID = UUID()

    private(set) var clock: HLCClock!
    private(set) var operationLog: OperationLog!
    private(set) var annotationEngine: AnnotationEngine!
    private(set) var tileCache: TileCache!
    private(set) var syncTransport: InMemorySyncTransport!
    private(set) var syncEngine: SyncEngine!
    private(set) var smartService: any SmartAnnotationService = MockSmartAnnotationService()
    private(set) var exporter = GeoJSONExporter()
    private(set) var kmlExporter = KMLExporter()

    private var hasBootstrapped = false

    // MARK: - Bootstrap

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        let dbDirectory = Self.applicationSupportDirectory()
        let opLogPath = dbDirectory.appendingPathComponent("operations.sqlite").path
        let tilePath = dbDirectory.appendingPathComponent("tiles.sqlite").path

        self.clock = HLCClock(nodeID: nodeID)
        self.operationLog = OperationLog(path: opLogPath)
        self.annotationEngine = AnnotationEngine(clock: clock, operationLog: operationLog)
        self.tileCache = TileCache(path: tilePath)
        self.syncTransport = InMemorySyncTransport()
        self.syncEngine = SyncEngine(transport: syncTransport, operationLog: operationLog)

        await reloadAnnotations()
    }

    // MARK: - Operations surfaced to views

    func reloadAnnotations() async {
        do {
            let current = try await operationLog.materializeProject(projectID: projectID)
            await annotationEngine.rebuildIndex(from: current)
            self.annotations = current
        } catch {
            self.annotations = []
            self.lastActionMessage = "Failed to load annotations: \(error)"
        }
    }

    /// Debug-menu helper: seed `count` synthetic pins clustered around San Francisco.
    func seedSyntheticAnnotations(count: Int) async {
        let center = GeoCoordinate(latitude: 37.7749, longitude: -122.4194)
        for i in 0..<count {
            let jitterLat = Double.random(in: -0.08...0.08)
            let jitterLon = Double.random(in: -0.08...0.08)
            let coordinate = GeoCoordinate(
                latitude: center.latitude + jitterLat,
                longitude: center.longitude + jitterLon
            )
            do {
                _ = try await annotationEngine.create(
                    type: .pin,
                    coordinate: coordinate,
                    title: "Seed \(i + 1)",
                    body: "Auto-generated demo pin",
                    projectID: projectID
                )
            } catch {
                self.lastActionMessage = "Seed failed at \(i): \(error)"
                break
            }
        }
        await reloadAnnotations()
        self.lastActionMessage = "Seeded \(count) annotations"
    }

    func clearAllAnnotations() async {
        for annotation in annotations {
            try? await annotationEngine.delete(annotationID: annotation.id, projectID: projectID)
        }
        await reloadAnnotations()
        self.lastActionMessage = "Cleared all annotations"
    }

    func addPin(at coordinate: GeoCoordinate, title: String = "Dropped Pin", body: String = "") async {
        do {
            _ = try await annotationEngine.create(
                type: .pin,
                coordinate: coordinate,
                title: title,
                body: body,
                projectID: projectID
            )
            await reloadAnnotations()
        } catch {
            self.lastActionMessage = "Add pin failed: \(error)"
        }
    }

    func toggleSync() async {
        syncEnabled.toggle()
        if syncEnabled {
            await performSync()
        } else {
            syncStatus = "disabled"
        }
    }

    func performSync() async {
        guard syncEnabled else { return }
        syncStatus = "syncing…"
        do {
            let unsynced = try await operationLog.unsynced()
            let remoteOps = try await syncEngine.sync(localUnsynced: unsynced)
            syncStatus = "idle · pushed \(unsynced.count), pulled \(remoteOps.count)"
            await reloadAnnotations()
        } catch {
            syncStatus = "error: \(error)"
        }
    }

    /// Debug-menu helper: kick off a bounding-box region download.
    ///
    /// TODO(CHA-135): wire to `RegionDownloader` when that ticket merges. Until
    /// then, walk the tile coordinates ourselves and drive the existing
    /// `TileCache` so the demo can exercise the cache path end-to-end.
    func downloadCurrentRegion(_ box: BoundingBox, zoomRange: ClosedRange<Int> = 12...14) async {
        regionDownloadProgress = 0.0
        let tileList = Self.tileCoordinates(in: box, zoomRange: zoomRange)
        guard !tileList.isEmpty else {
            regionDownloadProgress = 1.0
            lastActionMessage = "Region download: nothing to do"
            return
        }

        let source = selectedTileSource.source
        let session = URLSession(configuration: .default)
        var completed = 0

        for coord in tileList {
            if await tileCache.get(coord) != nil {
                completed += 1
                regionDownloadProgress = Double(completed) / Double(tileList.count)
                continue
            }
            let url = source.tileURL(for: coord)
            do {
                let (data, _) = try await session.data(from: url)
                await tileCache.put(coord, data: data)
            } catch {
                // Keep going: one missing tile does not fail the whole download.
            }
            completed += 1
            regionDownloadProgress = Double(completed) / Double(tileList.count)
        }
        lastActionMessage = "Region download complete (\(tileList.count) tiles)"
    }

    /// Collect GeoJSON bytes for the current project to hand to the share sheet.
    func currentGeoJSONExport() throws -> Data {
        try exporter.export(annotations: annotations, projectName: "Cartographer Demo")
    }

    // MARK: - Helpers

    private static func applicationSupportDirectory() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("CartographerDemo", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func tileCoordinates(
        in box: BoundingBox,
        zoomRange: ClosedRange<Int>
    ) -> [TileCoordinate] {
        var out: [TileCoordinate] = []
        for z in zoomRange {
            let nw = TileCoordinate.from(
                coordinate: GeoCoordinate(latitude: box.maxLatitude, longitude: box.minLongitude),
                zoom: z
            )
            let se = TileCoordinate.from(
                coordinate: GeoCoordinate(latitude: box.minLatitude, longitude: box.maxLongitude),
                zoom: z
            )
            let minX = min(nw.x, se.x)
            let maxX = max(nw.x, se.x)
            let minY = min(nw.y, se.y)
            let maxY = max(nw.y, se.y)
            for y in minY...maxY {
                for x in minX...maxX {
                    out.append(TileCoordinate(z: z, x: x, y: y))
                }
            }
        }
        return out
    }
}
