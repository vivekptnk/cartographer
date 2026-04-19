import Foundation
import Cartographer

/// Switchable tile sources exposed in the debug menu.
///
/// The demo ships two free, attribution-compliant providers so a reviewer can
/// verify the tile-source swap path without configuring API keys.
enum TileSourceChoice: String, CaseIterable, Identifiable {
    case openStreetMap
    case openTopoMap

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openStreetMap: return "OpenStreetMap"
        case .openTopoMap:   return "OpenTopoMap"
        }
    }

    var source: any TileSource {
        switch self {
        case .openStreetMap: return OpenStreetMapTileSource()
        case .openTopoMap:   return OpenTopoMapTileSource()
        }
    }
}

/// Secondary demo tile source so the UI has something to switch to. The real
/// engine continues to ship only OpenStreetMap; this stays colocated with the
/// demo because it is not a platform capability — it is a demo affordance.
struct OpenTopoMapTileSource: TileSource {
    let attribution = "© OpenStreetMap contributors, SRTM · OpenTopoMap (CC-BY-SA)"
    let maxZoom = 17

    func tileURL(for coordinate: TileCoordinate) -> URL {
        URL(string: "https://a.tile.opentopomap.org/\(coordinate.z)/\(coordinate.x)/\(coordinate.y).png")!
    }
}
