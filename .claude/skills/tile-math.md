# Tile Math for Cartographer

## Slippy Map Tile System (OSM Standard)

Tile coordinates: `(z, x, y)` where:
- `z` = zoom level (0-19). Zoom 0 = 1 tile covers Earth. Zoom 19 = ~0.3m per pixel.
- `x` = column (0 to 2^z - 1), left to right
- `y` = row (0 to 2^z - 1), top to bottom

## Coordinate ↔ Tile Conversion

```swift
// Geographic coordinate → tile coordinate
func tileFromCoordinate(lat: Double, lon: Double, zoom: Int) -> (x: Int, y: Int) {
    let n = Double(1 << zoom)
    let x = Int((lon + 180.0) / 360.0 * n)
    let latRad = lat * .pi / 180.0
    let y = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)
    return (x, y)
}

// Tile → bounding box (geographic coordinates)
func tileBoundingBox(x: Int, y: Int, zoom: Int) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
    let n = Double(1 << zoom)
    let lonMin = Double(x) / n * 360.0 - 180.0
    let lonMax = Double(x + 1) / n * 360.0 - 180.0
    let latMaxRad = atan(sinh(.pi * (1 - 2 * Double(y) / n)))
    let latMinRad = atan(sinh(.pi * (1 - 2 * Double(y + 1) / n)))
    return (latMinRad * 180 / .pi, latMaxRad * 180 / .pi, lonMin, lonMax)
}
```

## Tile URL Templates

```
OpenStreetMap: https://tile.openstreetmap.org/{z}/{x}/{y}.png
Mapbox: https://api.mapbox.com/v4/{tileset}/{z}/{x}/{y}.png?access_token={token}
Custom: Replace {z}, {x}, {y} in template URL
```

## Tiles for a Region

To download all tiles covering a bounding box at zoom levels zMin to zMax:

```swift
func tilesInRegion(bbox: BoundingBox, zoomMin: Int, zoomMax: Int) -> [TileCoordinate] {
    var tiles: [TileCoordinate] = []
    for z in zoomMin...zoomMax {
        let topLeft = tileFromCoordinate(lat: bbox.maxLatitude, lon: bbox.minLongitude, zoom: z)
        let bottomRight = tileFromCoordinate(lat: bbox.minLatitude, lon: bbox.maxLongitude, zoom: z)
        for x in topLeft.x...bottomRight.x {
            for y in topLeft.y...bottomRight.y {
                tiles.append(TileCoordinate(z: z, x: x, y: y))
            }
        }
    }
    return tiles
}
```

## Tile Count Formula

Total tiles at zoom z = `4^z` (or `2^z × 2^z`)

| Zoom | Tiles | Approx resolution |
|------|-------|-------------------|
| 0 | 1 | Whole world |
| 10 | 1M | City blocks |
| 15 | 1B | Individual buildings |
| 19 | 274B | Sub-meter |

## Cache Size Estimation

Average PNG tile ≈ 20-40KB. For a 10km × 10km region at zoom 10-16:
- Zoom 10: ~4 tiles × 30KB = 120KB
- Zoom 16: ~16K tiles × 30KB = 480MB

**Default cache limit: 500MB** with LRU eviction of oldest 20%.

## MKTileOverlay Integration

```swift
class CachedTileOverlay: MKTileOverlay {
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let coord = TileCoordinate(z: path.z, x: path.x, y: path.y)
        Task {
            if let cached = await tileCache.get(coord) {
                result(cached, nil)  // < 5ms target
            } else if isOnline {
                let data = try await fetchRemote(coord)
                await tileCache.put(coord, data: data)
                result(data, nil)
            } else {
                result(placeholderTile(), nil)  // Grey grid
            }
        }
    }
}
```
