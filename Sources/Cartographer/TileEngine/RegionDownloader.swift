// MARK: - Region Downloader
// Pre-caches every tile inside a BoundingBox at the requested zoom levels.
// Reports progress via AsyncStream. Resumes transparently: tiles already in
// the TileCache (SQLite) are counted as complete without hitting the network.

import Foundation

/// Snapshot of a region download, yielded on every state change.
public struct RegionDownloadProgress: Sendable, Hashable {
    public let totalTiles: Int
    public let completedTiles: Int
    public let failedTiles: Int
    public let currentTile: TileCoordinate?

    public init(
        totalTiles: Int,
        completedTiles: Int,
        failedTiles: Int,
        currentTile: TileCoordinate?
    ) {
        self.totalTiles = totalTiles
        self.completedTiles = completedTiles
        self.failedTiles = failedTiles
        self.currentTile = currentTile
    }

    public var isComplete: Bool { completedTiles + failedTiles >= totalTiles }
    public var fractionComplete: Double {
        guard totalTiles > 0 else { return 1.0 }
        return Double(completedTiles + failedTiles) / Double(totalTiles)
    }
}

/// Downloads every tile covered by a geographic region and a range of zoom levels
/// into a shared `TileCache`.
///
/// Resume semantics:
/// - `TileCache` is the persistent state. Running `download(region:zoomRange:)`
///   again with the same cache skips tiles already present, counting them as
///   completed in the first progress emission.
///
/// Background behavior:
/// - The default session is configured with `waitsForConnectivity = true` and a
///   generous resource timeout so in-progress downloads survive brief
///   backgrounding. Callers that need full background-transfer semantics can
///   inject a `URLSession` built from
///   `URLSessionConfiguration.background(withIdentifier:)`.
public actor RegionDownloader {
    private let cache: TileCache
    private let source: TileSource
    private let session: URLSession

    public init(
        cache: TileCache,
        source: TileSource,
        session: URLSession = RegionDownloader.defaultSession()
    ) {
        self.cache = cache
        self.source = source
        self.session = session
    }

    /// Session suitable for region pre-caching. Waits for connectivity, tolerates
    /// long transfers, and works while the app is foreground or briefly backgrounded.
    public static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 300
        config.allowsCellularAccess = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }

    // MARK: - Enumeration

    /// Every `(z, x, y)` that intersects `region`, for each zoom in `zoomRange`.
    public nonisolated func tileCoordinates(
        for region: BoundingBox,
        zoomRange: ClosedRange<Int>
    ) -> [TileCoordinate] {
        var coords: [TileCoordinate] = []
        for z in zoomRange {
            let nw = TileCoordinate.from(
                coordinate: GeoCoordinate(latitude: region.maxLatitude, longitude: region.minLongitude),
                zoom: z
            )
            let se = TileCoordinate.from(
                coordinate: GeoCoordinate(latitude: region.minLatitude, longitude: region.maxLongitude),
                zoom: z
            )
            let axis = 1 << z
            let xStart = max(0, min(nw.x, se.x))
            let xEnd = min(axis - 1, max(nw.x, se.x))
            let yStart = max(0, min(nw.y, se.y))
            let yEnd = min(axis - 1, max(nw.y, se.y))
            guard xStart <= xEnd, yStart <= yEnd else { continue }
            for x in xStart...xEnd {
                for y in yStart...yEnd {
                    coords.append(TileCoordinate(z: z, x: x, y: y))
                }
            }
        }
        return coords
    }

    // MARK: - Download

    /// Streams progress for the given region + zoom range. The stream terminates
    /// when every tile has been accounted for (cached, downloaded, or failed).
    public nonisolated func download(
        region: BoundingBox,
        zoomRange: ClosedRange<Int>
    ) -> AsyncStream<RegionDownloadProgress> {
        let coords = tileCoordinates(for: region, zoomRange: zoomRange)
        return AsyncStream { continuation in
            let task = Task {
                await self.run(coords: coords, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        coords: [TileCoordinate],
        continuation: AsyncStream<RegionDownloadProgress>.Continuation
    ) async {
        let total = coords.count
        var completed = 0
        var failed = 0

        // Initial snapshot — callers see the plan before any work starts.
        continuation.yield(
            RegionDownloadProgress(totalTiles: total, completedTiles: 0, failedTiles: 0, currentTile: nil)
        )

        for coord in coords {
            if Task.isCancelled { break }

            if await cache.get(coord) != nil {
                completed += 1
                continuation.yield(
                    RegionDownloadProgress(
                        totalTiles: total,
                        completedTiles: completed,
                        failedTiles: failed,
                        currentTile: coord
                    )
                )
                continue
            }

            let url = source.tileURL(for: coord)
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    failed += 1
                } else if data.isEmpty {
                    failed += 1
                } else {
                    await cache.put(coord, data: data)
                    completed += 1
                }
            } catch {
                failed += 1
            }

            continuation.yield(
                RegionDownloadProgress(
                    totalTiles: total,
                    completedTiles: completed,
                    failedTiles: failed,
                    currentTile: coord
                )
            )
        }

        continuation.finish()
    }
}
