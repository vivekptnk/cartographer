// MARK: - Caching Tile Overlay
// MKTileOverlay subclass with cache-first semantics.
// Lookup order: TileCache (SQLite) → remote via URLSession → placeholder on offline miss.

import Foundation
#if canImport(MapKit)
@preconcurrency import MapKit

/// MKTileOverlay that reads through a persistent TileCache before hitting the network.
///
/// - Cache hit: returns the stored `Data` without a network round-trip.
/// - Cache miss, online: fetches via URLSession, stores in the cache, returns `Data`.
/// - Cache miss, offline: returns a grey-grid placeholder. Never calls back with an error.
///
/// MapKit calls `loadTile(at:result:)` off the main thread. We do the async cache +
/// network work on a detached Task and invoke the result callback when finished.
public final class CachingTileOverlay: MKTileOverlay, @unchecked Sendable {
    private let source: TileSource
    private let cache: TileCache
    private let session: URLSession

    public init(source: TileSource, cache: TileCache, session: URLSession = .shared) {
        self.source = source
        self.cache = cache
        self.session = session
        // Empty template forces MapKit to call url(forTilePath:), which we override.
        super.init(urlTemplate: "")
        self.canReplaceMapContent = true
        self.maximumZ = source.maxZoom
        self.tileSize = CGSize(width: 256, height: 256)
    }

    public override func url(forTilePath path: MKTileOverlayPath) -> URL {
        source.tileURL(for: TileCoordinate(z: path.z, x: path.x, y: path.y))
    }

    public override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, (any Error)?) -> Void
    ) {
        let coord = TileCoordinate(z: path.z, x: path.x, y: path.y)
        let callback = UncheckedSendableBox(value: result)
        let cache = self.cache
        let session = self.session
        let source = self.source

        Task.detached {
            let data = await Self.fetch(coord: coord, cache: cache, session: session, source: source)
            callback.value(data, nil)
        }
    }

    /// Exposed for tests. Resolves a tile using the same cache-first semantics as
    /// `loadTile(at:result:)` but with a plain async signature.
    public func tileData(for coord: TileCoordinate) async -> Data {
        await Self.fetch(coord: coord, cache: cache, session: session, source: source)
    }

    private static func fetch(
        coord: TileCoordinate,
        cache: TileCache,
        session: URLSession,
        source: TileSource
    ) async -> Data {
        if let cached = await cache.get(coord) {
            return cached
        }

        let url = source.tileURL(for: coord)
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return PlaceholderTile.data
            }
            guard !data.isEmpty else { return PlaceholderTile.data }
            await cache.put(coord, data: data)
            return data
        } catch {
            return PlaceholderTile.data
        }
    }
}

/// Lightweight Sendable wrapper for callbacks whose Sendability is unknown to the compiler.
/// Safety: the wrapped value is read at most once on the Task that receives the tile data.
private final class UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(value: T) { self.value = value }
}

#endif
