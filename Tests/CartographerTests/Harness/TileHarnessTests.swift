// MARK: - Tile Engine Harness Tests
// Defines the behavioral contract for tile caching, coordinate math, and overlay.
// RULE: Never modify this file to make tests pass. Fix the implementation instead.

import XCTest
@testable import Cartographer
#if canImport(MapKit)
import MapKit
#endif

final class TileHarnessTests: XCTestCase {

    // MARK: - TileCoordinate Math

    func testTileCoordinate_FromCoordinate_Zoom0() {
        // At zoom 0, the entire world is one tile (0, 0, 0)
        let tile = TileCoordinate.from(
            coordinate: GeoCoordinate(latitude: 0, longitude: 0),
            zoom: 0
        )
        XCTAssertEqual(tile.z, 0)
        XCTAssertEqual(tile.x, 0)
        XCTAssertEqual(tile.y, 0)
    }

    func testTileCoordinate_FromCoordinate_NYC() {
        // NYC ~(40.7128, -74.0060) at zoom 10
        let tile = TileCoordinate.from(
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
            zoom: 10
        )
        XCTAssertEqual(tile.z, 10)
        // Known tile coords for NYC at z=10: x=301, y=384 (approximately)
        XCTAssertTrue((300...302).contains(tile.x), "NYC x tile should be ~301 at z=10, got \(tile.x)")
        XCTAssertTrue((383...385).contains(tile.y), "NYC y tile should be ~384 at z=10, got \(tile.y)")
    }

    func testTileCoordinate_BoundingBox_ContainsOriginalPoint() {
        let coord = GeoCoordinate(latitude: 48.8566, longitude: 2.3522) // Paris
        let tile = TileCoordinate.from(coordinate: coord, zoom: 12)
        let bbox = tile.boundingBox
        XCTAssertTrue(bbox.contains(coord), "Tile bounding box must contain the coordinate that generated it")
    }

    func testTileCoordinate_TilesPerAxis() {
        XCTAssertEqual(TileCoordinate(z: 0, x: 0, y: 0).tilesPerAxis, 1)
        XCTAssertEqual(TileCoordinate(z: 1, x: 0, y: 0).tilesPerAxis, 2)
        XCTAssertEqual(TileCoordinate(z: 10, x: 0, y: 0).tilesPerAxis, 1024)
    }

    // MARK: - BoundingBox Tests

    func testBoundingBox_Intersects() {
        let a = BoundingBox(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10)
        let b = BoundingBox(minLatitude: 5, maxLatitude: 15, minLongitude: 5, maxLongitude: 15)
        XCTAssertTrue(a.intersects(b))
        XCTAssertTrue(b.intersects(a), "Intersection must be symmetric")
    }

    func testBoundingBox_DoesNotIntersect() {
        let a = BoundingBox(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10)
        let b = BoundingBox(minLatitude: 20, maxLatitude: 30, minLongitude: 20, maxLongitude: 30)
        XCTAssertFalse(a.intersects(b))
    }

    func testBoundingBox_Contains() {
        let box = BoundingBox(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10)
        XCTAssertTrue(box.contains(GeoCoordinate(latitude: 5, longitude: 5)))
        XCTAssertTrue(box.contains(GeoCoordinate(latitude: 0, longitude: 0)), "Boundary should be inclusive")
        XCTAssertFalse(box.contains(GeoCoordinate(latitude: 15, longitude: 5)))
    }

    func testBoundingBox_Union() {
        let a = BoundingBox(minLatitude: 0, maxLatitude: 5, minLongitude: 0, maxLongitude: 5)
        let b = BoundingBox(minLatitude: 3, maxLatitude: 10, minLongitude: 3, maxLongitude: 10)
        let u = a.union(b)
        XCTAssertEqual(u.minLatitude, 0)
        XCTAssertEqual(u.maxLatitude, 10)
        XCTAssertEqual(u.minLongitude, 0)
        XCTAssertEqual(u.maxLongitude, 10)
    }

    func testBoundingBox_Area() {
        let box = BoundingBox(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10)
        XCTAssertEqual(box.area, 100.0, accuracy: 0.001)
    }

    // MARK: - Annotation BoundingBox

    func testAnnotation_PinBoundingBox_IsPoint() {
        let pin = Annotation(
            type: .pin,
            coordinate: GeoCoordinate(latitude: 40.0, longitude: -74.0),
            projectID: UUID()
        )
        let bbox = pin.boundingBox
        XCTAssertEqual(bbox.minLatitude, bbox.maxLatitude)
        XCTAssertEqual(bbox.minLongitude, bbox.maxLongitude)
    }

    func testAnnotation_RouteBoundingBox_EnclosesAllPoints() {
        let coords = [
            GeoCoordinate(latitude: 10, longitude: 20),
            GeoCoordinate(latitude: 30, longitude: 40),
            GeoCoordinate(latitude: 5, longitude: 50),
        ]
        let route = Annotation(
            type: .route,
            coordinate: coords[0],
            routeCoordinates: coords,
            projectID: UUID()
        )
        let bbox = route.boundingBox
        for coord in coords {
            XCTAssertTrue(bbox.contains(coord), "Route bbox must contain all route coordinates")
        }
    }

    // MARK: - Annotation Codable Round-Trip

    func testAnnotation_CodableRoundTrip_AllTypes() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in AnnotationType.allCases {
            let original = Annotation(
                type: type,
                coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
                title: "Test \(type.rawValue)",
                body: "Body text",
                routeCoordinates: type == .route ? [
                    GeoCoordinate(latitude: 40.7, longitude: -74.0),
                    GeoCoordinate(latitude: 40.8, longitude: -74.1),
                ] : nil,
                polygonCoordinates: type == .polygon ? [
                    GeoCoordinate(latitude: 40.7, longitude: -74.0),
                    GeoCoordinate(latitude: 40.8, longitude: -74.0),
                    GeoCoordinate(latitude: 40.8, longitude: -74.1),
                ] : nil,
                metadata: ["key": "value"],
                projectID: UUID()
            )

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(Annotation.self, from: data)

            XCTAssertEqual(decoded.id, original.id)
            XCTAssertEqual(decoded.type, original.type)
            XCTAssertEqual(decoded.coordinate, original.coordinate)
            XCTAssertEqual(decoded.title, original.title)
            XCTAssertEqual(decoded.body, original.body)
            XCTAssertEqual(decoded.routeCoordinates, original.routeCoordinates)
            XCTAssertEqual(decoded.polygonCoordinates, original.polygonCoordinates)
            XCTAssertEqual(decoded.metadata, original.metadata)
        }
    }

    // MARK: - CachingTileOverlay

    #if canImport(MapKit)

    func testCachingTileOverlay_CacheHit_ReturnsCachedData() async {
        let cache = TileCache(maxCacheSize: 1 * 1024 * 1024)
        let coord = TileCoordinate(z: 10, x: 301, y: 384)
        let tileData = Data(repeating: 0xCA, count: 512)
        await cache.put(coord, data: tileData)

        let session = TileHarnessStub.session(reject: "cache hit must not touch network")
        let overlay = CachingTileOverlay(source: OpenStreetMapTileSource(), cache: cache, session: session)

        let result = await overlay.tileData(for: coord)
        XCTAssertEqual(result, tileData, "Cache hit should return the stored bytes exactly")
    }

    func testCachingTileOverlay_CacheMissOnline_FetchesAndStores() async {
        let cache = TileCache(maxCacheSize: 1 * 1024 * 1024)
        let coord = TileCoordinate(z: 12, x: 2048, y: 1361)
        let remoteBytes = Data(repeating: 0x42, count: 1024)
        let expectedURL = OpenStreetMapTileSource().tileURL(for: coord)

        let session = TileHarnessStub.session(for: [expectedURL: .success(remoteBytes)])
        let overlay = CachingTileOverlay(source: OpenStreetMapTileSource(), cache: cache, session: session)

        let fetched = await overlay.tileData(for: coord)
        XCTAssertEqual(fetched, remoteBytes, "Online cache miss must return the fetched bytes")

        let persisted = await cache.get(coord)
        XCTAssertEqual(persisted, remoteBytes, "Fetched tiles must be written to the cache")
    }

    func testCachingTileOverlay_CacheMissOffline_ReturnsPlaceholder() async {
        let cache = TileCache(maxCacheSize: 1 * 1024 * 1024)
        let coord = TileCoordinate(z: 8, x: 75, y: 96)

        let session = TileHarnessStub.session(
            for: [:],
            defaultResponse: .failure(URLError(.notConnectedToInternet))
        )
        let overlay = CachingTileOverlay(source: OpenStreetMapTileSource(), cache: cache, session: session)

        let data = await overlay.tileData(for: coord)
        XCTAssertFalse(data.isEmpty, "Offline cache miss must still return a non-empty placeholder — never throw out to MapKit")
        XCTAssertEqual(data, PlaceholderTile.data, "Offline misses resolve to the shared grey-grid placeholder")

        let persisted = await cache.get(coord)
        XCTAssertNil(persisted, "Placeholder tiles must NOT be written to the cache")
    }

    #endif

    // MARK: - RegionDownloader

    func testRegionDownloader_EnumeratesTilesCoveringRegion() async {
        let cache = TileCache(maxCacheSize: 1 * 1024 * 1024)
        let downloader = RegionDownloader(cache: cache, source: OpenStreetMapTileSource())
        // ~Manhattan-sized box at z=10.
        let region = BoundingBox(minLatitude: 40.70, maxLatitude: 40.80, minLongitude: -74.02, maxLongitude: -73.93)
        let coords = downloader.tileCoordinates(for: region, zoomRange: 10...10)
        XCTAssertFalse(coords.isEmpty, "Enumeration must cover the requested region")
        for coord in coords {
            XCTAssertEqual(coord.z, 10)
            XCTAssertTrue(coord.x >= 0 && coord.x < (1 << 10))
            XCTAssertTrue(coord.y >= 0 && coord.y < (1 << 10))
        }
    }

    func testRegionDownloader_ReportsAccurateProgress() async {
        let cache = TileCache(maxCacheSize: 1 * 1024 * 1024)
        let source = OpenStreetMapTileSource()
        // Tiny box that resolves to a single tile at z=1.
        let region = BoundingBox(minLatitude: 10, maxLatitude: 11, minLongitude: 10, maxLongitude: 11)
        let zoomRange = 1...1

        let responder = RegionDownloader(cache: cache, source: source)
        let coords = responder.tileCoordinates(for: region, zoomRange: zoomRange)
        XCTAssertFalse(coords.isEmpty)

        let fakeBytes = Data(repeating: 0x11, count: 32)
        var map: [URL: TileHarnessStub.Outcome] = [:]
        for coord in coords {
            map[source.tileURL(for: coord)] = .success(fakeBytes)
        }
        let session = TileHarnessStub.session(for: map)
        let downloader = RegionDownloader(cache: cache, source: source, session: session)

        var lastProgress: RegionDownloadProgress?
        for await progress in downloader.download(region: region, zoomRange: zoomRange) {
            lastProgress = progress
            XCTAssertEqual(progress.totalTiles, coords.count)
            XCTAssertLessThanOrEqual(progress.completedTiles + progress.failedTiles, progress.totalTiles)
        }

        let final = try? XCTUnwrap(lastProgress)
        XCTAssertEqual(final?.totalTiles, coords.count)
        XCTAssertEqual(final?.completedTiles, coords.count, "All tiles should be reported completed")
        XCTAssertEqual(final?.failedTiles, 0)

        for coord in coords {
            let persisted = await cache.get(coord)
            XCTAssertEqual(persisted, fakeBytes, "Downloaded tiles must be persisted")
        }
    }

    func testRegionDownloader_ResumesFromCacheAfterRestart() async {
        // Simulates: first launch downloads some tiles, app terminates,
        // second launch starts a fresh downloader pointing at the same cache file.
        // The second downloader must count cached tiles as complete and NOT re-fetch.
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("resume_\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let source = OpenStreetMapTileSource()
        let region = BoundingBox(minLatitude: 0, maxLatitude: 1, minLongitude: 0, maxLongitude: 1)
        let zoomRange = 3...3

        // Prepare: every coordinate mapped to a deterministic byte pattern.
        let plan = RegionDownloader(cache: TileCache(maxCacheSize: 1, path: ":memory:"), source: source)
            .tileCoordinates(for: region, zoomRange: zoomRange)
        XCTAssertFalse(plan.isEmpty)
        var responses: [URL: TileHarnessStub.Outcome] = [:]
        for coord in plan {
            responses[source.tileURL(for: coord)] = .success(Data([UInt8(coord.x & 0xFF), UInt8(coord.y & 0xFF)]))
        }

        // First "launch": cache some of the tiles via a real download pass.
        do {
            let cache = TileCache(maxCacheSize: 10 * 1024 * 1024, path: dbPath)
            let session = TileHarnessStub.session(for: responses)
            let downloader = RegionDownloader(cache: cache, source: source, session: session)
            for await _ in downloader.download(region: region, zoomRange: zoomRange) {}
            let count = await cache.tileCount()
            XCTAssertEqual(count, plan.count, "First launch should populate the cache")
        }

        // Second "launch": new cache instance on the same file, network hard-fails.
        // Every tile must still be resolved from the persistent cache.
        let cache2 = TileCache(maxCacheSize: 10 * 1024 * 1024, path: dbPath)
        let offlineSession = TileHarnessStub.session(
            for: [:],
            defaultResponse: .failure(URLError(.notConnectedToInternet))
        )
        let downloader2 = RegionDownloader(cache: cache2, source: source, session: offlineSession)

        var final: RegionDownloadProgress?
        for await progress in downloader2.download(region: region, zoomRange: zoomRange) {
            final = progress
        }
        XCTAssertNotNil(final)
        XCTAssertEqual(final?.totalTiles, plan.count)
        XCTAssertEqual(final?.completedTiles, plan.count, "Resumed run must count cached tiles as complete")
        XCTAssertEqual(final?.failedTiles, 0, "No failures expected when every tile is already cached")
    }
}

// MARK: - Test Fixtures

/// URLProtocol-based stub for injecting canned responses into URLSession.
/// Each test owns its own isolated routing table via a registry keyed by
/// session configuration identifier.
final class TileHarnessStub: URLProtocol, @unchecked Sendable {
    enum Outcome {
        case success(Data)
        case failure(Error)
    }

    private struct Routing {
        let responses: [URL: Outcome]
        let defaultResponse: Outcome?
    }

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: Routing] = [:]
    private static let headerKey = "X-TileHarnessStub-Id"

    static func session(
        for responses: [URL: Outcome] = [:],
        defaultResponse: Outcome? = nil
    ) -> URLSession {
        let id = UUID().uuidString
        registryLock.lock()
        registry[id] = Routing(responses: responses, defaultResponse: defaultResponse)
        registryLock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TileHarnessStub.self]
        config.httpAdditionalHeaders = [headerKey: id]
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }

    /// Convenience for tests that must guarantee zero network activity.
    static func session(reject message: String) -> URLSession {
        session(for: [:], defaultResponse: .failure(NSError(domain: "TileHarnessStub", code: -1, userInfo: [NSLocalizedDescriptionKey: message])))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let id = request.value(forHTTPHeaderField: Self.headerKey),
            let routing = Self.routing(for: id),
            let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let outcome = routing.responses[url] ?? routing.defaultResponse
        switch outcome {
        case .some(.success(let data)):
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .some(.failure(let error)):
            client?.urlProtocol(self, didFailWithError: error)
        case .none:
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
        }
    }

    override func stopLoading() {}

    private static func routing(for id: String) -> Routing? {
        registryLock.lock()
        defer { registryLock.unlock() }
        return registry[id]
    }
}
