// MARK: - Map Clusterer
// Grid-based clustering. Bucket annotations by a degree-space cell grid and
// emit one `MapCluster` per non-empty cell. This is O(N) in the number of
// visible annotations and deterministic (no tie-breaking by iteration order),
// which makes it reliable to assert on in the harness.

import Foundation

public enum MapClusterer {
    /// Bucket a set of annotations into `MapCluster`s using a degree-space grid.
    ///
    /// Each member is placed in the cell `(floor(lon/cell), floor(lat/cell))`.
    /// Cells with exactly one member produce a degenerate cluster whose `id`
    /// equals that member's id, so downstream rendering can reuse MKAnnotation
    /// identity for stable views. Multi-member cells produce a synthetic id
    /// so re-clustering doesn't collide with any annotation id.
    ///
    /// Output is sorted descending by `count`, stably tie-broken by the
    /// cluster's representative latitude/longitude, so repeated calls with
    /// the same input yield the same output (important for diffing).
    public static func cluster(
        annotations: [(id: EntityID, coordinate: GeoCoordinate)],
        cellSizeDegrees cell: Double
    ) -> [MapCluster] {
        precondition(cell > 0, "cell size must be positive")
        guard !annotations.isEmpty else { return [] }

        var buckets: [Cell: Bucket] = [:]
        buckets.reserveCapacity(annotations.count)
        for (id, coord) in annotations {
            let key = Cell(
                x: Int(floor(coord.longitude / cell)),
                y: Int(floor(coord.latitude / cell))
            )
            var bucket = buckets[key] ?? Bucket()
            bucket.ids.append(id)
            bucket.sumLat += coord.latitude
            bucket.sumLon += coord.longitude
            buckets[key] = bucket
        }

        var out: [MapCluster] = []
        out.reserveCapacity(buckets.count)
        for (key, bucket) in buckets {
            let count = Double(bucket.ids.count)
            let center = GeoCoordinate(
                latitude: bucket.sumLat / count,
                longitude: bucket.sumLon / count
            )
            let lat0 = Double(key.y) * cell
            let lon0 = Double(key.x) * cell
            let bbox = BoundingBox(
                minLatitude: lat0,
                maxLatitude: lat0 + cell,
                minLongitude: lon0,
                maxLongitude: lon0 + cell
            )
            let repID = bucket.ids.count == 1
                ? bucket.ids[0]
                : Self.syntheticID(for: key)
            out.append(MapCluster(
                id: repID,
                coordinate: center,
                boundingBox: bbox,
                memberIDs: bucket.ids
            ))
        }

        out.sort { lhs, rhs in
            if lhs.memberIDs.count != rhs.memberIDs.count {
                return lhs.memberIDs.count > rhs.memberIDs.count
            }
            if lhs.coordinate.latitude != rhs.coordinate.latitude {
                return lhs.coordinate.latitude < rhs.coordinate.latitude
            }
            return lhs.coordinate.longitude < rhs.coordinate.longitude
        }
        return out
    }

    private struct Bucket {
        var ids: [EntityID] = []
        var sumLat: Double = 0
        var sumLon: Double = 0
    }

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    /// Deterministic UUID derived from grid cell coordinates so equivalent
    /// re-clusters keep the same cluster id and diffs remain stable.
    private static func syntheticID(for cell: Cell) -> EntityID {
        var bytes = [UInt8](repeating: 0, count: 16)
        // High byte marker so synthetic ids are trivially distinguishable in
        // logs — this is not a security boundary.
        bytes[0] = 0xC1
        bytes[1] = 0x05
        let x = UInt64(bitPattern: Int64(cell.x))
        let y = UInt64(bitPattern: Int64(cell.y))
        for i in 0..<8 { bytes[2 + i] = UInt8((x >> (i * 8)) & 0xFF) }
        for i in 0..<6 { bytes[10 + i] = UInt8((y >> (i * 8)) & 0xFF) }
        return EntityID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
