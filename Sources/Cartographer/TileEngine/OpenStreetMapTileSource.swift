// MARK: - OpenStreetMap Tile Source
// Default tile source using OSM's public tile server.

import Foundation

/// OpenStreetMap tile source. Free, open data, standard slippy map format.
public struct OpenStreetMapTileSource: TileSource {
    public let attribution: String = "© OpenStreetMap contributors"
    public let maxZoom: Int = 19

    public init() {}

    public func tileURL(for coordinate: TileCoordinate) -> URL {
        URL(string: "https://tile.openstreetmap.org/\(coordinate.z)/\(coordinate.x)/\(coordinate.y).png")!
    }
}
