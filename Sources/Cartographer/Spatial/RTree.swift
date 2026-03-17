// MARK: - R-Tree Spatial Index
// A balanced tree for spatial queries over 2D bounding boxes.
// Supports: insert, delete, range query, nearest-neighbor, bulk load (STR).

import Foundation

/// An entry in the R-tree: an element with a bounding box.
public struct RTreeEntry<Element: Sendable & Hashable>: Sendable, Hashable {
    public let element: Element
    public let boundingBox: BoundingBox

    public init(element: Element, boundingBox: BoundingBox) {
        self.element = element
        self.boundingBox = boundingBox
    }
}

/// R-tree node. Internal nodes have children; leaf nodes have entries.
public indirect enum RTreeNode<Element: Sendable & Hashable>: Sendable {
    case leaf(entries: [RTreeEntry<Element>])
    case `internal`(children: [(boundingBox: BoundingBox, node: RTreeNode<Element>)])

    var boundingBox: BoundingBox {
        switch self {
        case .leaf(let entries):
            guard let first = entries.first else {
                return BoundingBox(minLatitude: 0, maxLatitude: 0, minLongitude: 0, maxLongitude: 0)
            }
            return entries.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
        case .internal(let children):
            guard let first = children.first else {
                return BoundingBox(minLatitude: 0, maxLatitude: 0, minLongitude: 0, maxLongitude: 0)
            }
            return children.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
        }
    }
}

/// R-tree with configurable max entries per node.
/// Value type — safe to copy across isolation boundaries.
public struct RTree<Element: Sendable & Hashable>: Sendable {
    public let maxEntries: Int
    public private(set) var root: RTreeNode<Element>?
    public private(set) var count: Int

    public init(maxEntries: Int = 16) {
        precondition(maxEntries >= 4, "maxEntries must be at least 4")
        self.maxEntries = maxEntries
        self.root = nil
        self.count = 0
    }

    // MARK: - Public API (to be implemented)

    /// Insert an entry into the tree.
    public mutating func insert(_ entry: RTreeEntry<Element>) {
        // TODO: Implement — choose leaf, insert, split if overflow, propagate up
        fatalError("Not yet implemented — implement for CG-005")
    }

    /// Remove an entry from the tree.
    @discardableResult
    public mutating func remove(_ element: Element) -> Bool {
        // TODO: Implement — find leaf, remove entry, condense tree
        fatalError("Not yet implemented — implement for CG-005")
    }

    /// Search for all entries whose bounding box intersects the query box.
    public func search(in box: BoundingBox) -> [RTreeEntry<Element>] {
        // TODO: Implement — recursive descent, prune non-intersecting branches
        fatalError("Not yet implemented — implement for CG-005")
    }

    /// Find the nearest entry to a point.
    public func nearest(to point: GeoCoordinate, maxDistance: Double = .greatestFiniteMagnitude) -> RTreeEntry<Element>? {
        // TODO: Implement — priority queue branch-and-bound
        fatalError("Not yet implemented — implement for CG-005")
    }

    /// Bulk load from a sorted array using Sort-Tile-Recursive (STR).
    public static func bulkLoad(_ entries: [RTreeEntry<Element>], maxEntries: Int = 16) -> RTree<Element> {
        // TODO: Implement — sort by x, partition into slabs, sort each slab by y, build bottom-up
        fatalError("Not yet implemented — implement for CG-005")
    }

    public var isEmpty: Bool { count == 0 }
}
