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

    // MARK: - Public API

    /// Insert an entry into the tree.
    public mutating func insert(_ entry: RTreeEntry<Element>) {
        guard let root = root else {
            self.root = .leaf(entries: [entry])
            count = 1
            return
        }
        let result = Self.insertIntoNode(entry, node: root, maxEntries: maxEntries)
        switch result {
        case .fit(let node):
            self.root = node
        case .split(let left, let right):
            self.root = .internal(children: [
                (boundingBox: left.boundingBox, node: left),
                (boundingBox: right.boundingBox, node: right),
            ])
        }
        count += 1
    }

    /// Remove an entry from the tree.
    @discardableResult
    public mutating func remove(_ element: Element) -> Bool {
        guard let root = root else { return false }
        var orphans: [RTreeEntry<Element>] = []
        guard let newRoot = Self.removeFromNode(element, node: root, minEntries: max(maxEntries / 2, 2), orphans: &orphans) else {
            return false
        }
        count -= 1

        // Collapse root if internal with single child
        var collapsed = newRoot
        while case .internal(let children) = collapsed, children.count == 1 {
            collapsed = children[0].node
        }

        // Handle empty tree
        if count == 0 {
            self.root = nil
        } else {
            self.root = collapsed
        }

        // Re-insert orphaned entries (without double-counting)
        for orphan in orphans {
            insertWithoutCounting(orphan)
        }
        return true
    }

    /// Search for all entries whose bounding box intersects the query box.
    public func search(in box: BoundingBox) -> [RTreeEntry<Element>] {
        guard let root = root else { return [] }
        var results: [RTreeEntry<Element>] = []
        Self.searchNode(root, box: box, results: &results)
        return results
    }

    /// Find the nearest entry to a point.
    public func nearest(to point: GeoCoordinate, maxDistance: Double = .greatestFiniteMagnitude) -> RTreeEntry<Element>? {
        guard let root = root else { return nil }
        var bestDistSq = maxDistance == .greatestFiniteMagnitude
            ? Double.greatestFiniteMagnitude
            : maxDistance * maxDistance
        var bestEntry: RTreeEntry<Element>?
        Self.nearestInNode(root, point: point, bestDistSq: &bestDistSq, bestEntry: &bestEntry)
        return bestEntry
    }

    /// Bulk load from a sorted array using Sort-Tile-Recursive (STR).
    public static func bulkLoad(_ entries: [RTreeEntry<Element>], maxEntries: Int = 16) -> RTree<Element> {
        precondition(maxEntries >= 4, "maxEntries must be at least 4")
        var tree = RTree(maxEntries: maxEntries)
        guard !entries.isEmpty else { return tree }
        tree.count = entries.count
        tree.root = buildSTR(entries, maxEntries: maxEntries)
        return tree
    }

    public var isEmpty: Bool { count == 0 }

    /// Insert an entry without modifying count (used for orphan reinsertion).
    private mutating func insertWithoutCounting(_ entry: RTreeEntry<Element>) {
        guard let root = root else {
            self.root = .leaf(entries: [entry])
            return
        }
        let result = Self.insertIntoNode(entry, node: root, maxEntries: maxEntries)
        switch result {
        case .fit(let node):
            self.root = node
        case .split(let left, let right):
            self.root = .internal(children: [
                (boundingBox: left.boundingBox, node: left),
                (boundingBox: right.boundingBox, node: right),
            ])
        }
    }

    // MARK: - Insert Internals

    private enum InsertResult {
        case fit(RTreeNode<Element>)
        case split(RTreeNode<Element>, RTreeNode<Element>)
    }

    private static func insertIntoNode(
        _ entry: RTreeEntry<Element>,
        node: RTreeNode<Element>,
        maxEntries: Int
    ) -> InsertResult {
        switch node {
        case .leaf(var entries):
            entries.append(entry)
            if entries.count <= maxEntries {
                return .fit(.leaf(entries: entries))
            }
            let (left, right) = quadraticSplitLeaf(entries, maxEntries: maxEntries)
            return .split(.leaf(entries: left), .leaf(entries: right))

        case .internal(var children):
            let bestIdx = chooseSubtree(children, for: entry.boundingBox)
            let result = insertIntoNode(entry, node: children[bestIdx].node, maxEntries: maxEntries)

            switch result {
            case .fit(let updated):
                children[bestIdx] = (boundingBox: updated.boundingBox, node: updated)
                return .fit(.internal(children: children))
            case .split(let left, let right):
                children.remove(at: bestIdx)
                children.append((boundingBox: left.boundingBox, node: left))
                children.append((boundingBox: right.boundingBox, node: right))
                if children.count <= maxEntries {
                    return .fit(.internal(children: children))
                }
                let (lc, rc) = quadraticSplitInternal(children, maxEntries: maxEntries)
                return .split(.internal(children: lc), .internal(children: rc))
            }
        }
    }

    private static func chooseSubtree(
        _ children: [(boundingBox: BoundingBox, node: RTreeNode<Element>)],
        for box: BoundingBox
    ) -> Int {
        var bestIdx = 0
        var bestEnlargement = Double.greatestFiniteMagnitude
        var bestArea = Double.greatestFiniteMagnitude
        for i in children.indices {
            let enlargedArea = children[i].boundingBox.union(box).area
            let enlargement = enlargedArea - children[i].boundingBox.area
            if enlargement < bestEnlargement
                || (enlargement == bestEnlargement && children[i].boundingBox.area < bestArea)
            {
                bestEnlargement = enlargement
                bestArea = children[i].boundingBox.area
                bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - Quadratic Split

    private static func quadraticSplitLeaf(
        _ entries: [RTreeEntry<Element>],
        maxEntries: Int
    ) -> ([RTreeEntry<Element>], [RTreeEntry<Element>]) {
        let boxes = entries.map(\.boundingBox)
        let (s1, s2) = pickSeeds(boxes)
        let minFill = max(maxEntries * 2 / 5, 2)
        var groupA = [entries[s1]]
        var groupB = [entries[s2]]
        var bbA = entries[s1].boundingBox
        var bbB = entries[s2].boundingBox
        var assigned = Set([s1, s2])

        for _ in 0..<entries.count {
            if assigned.count == entries.count { break }
            // If one group needs all remaining to reach minFill
            let remaining = entries.count - assigned.count
            if groupA.count + remaining == minFill {
                for i in entries.indices where !assigned.contains(i) { groupA.append(entries[i]) }
                break
            }
            if groupB.count + remaining == minFill {
                for i in entries.indices where !assigned.contains(i) { groupB.append(entries[i]) }
                break
            }
            // Pick the entry with greatest preference difference
            var bestIdx = -1
            var bestDiff = -Double.greatestFiniteMagnitude
            for i in entries.indices where !assigned.contains(i) {
                let dA = bbA.union(entries[i].boundingBox).area - bbA.area
                let dB = bbB.union(entries[i].boundingBox).area - bbB.area
                let diff = abs(dA - dB)
                if diff > bestDiff {
                    bestDiff = diff
                    bestIdx = i
                }
            }
            guard bestIdx >= 0 else { break }
            let dA = bbA.union(entries[bestIdx].boundingBox).area - bbA.area
            let dB = bbB.union(entries[bestIdx].boundingBox).area - bbB.area
            if dA < dB || (dA == dB && bbA.area <= bbB.area) {
                groupA.append(entries[bestIdx])
                bbA = bbA.union(entries[bestIdx].boundingBox)
            } else {
                groupB.append(entries[bestIdx])
                bbB = bbB.union(entries[bestIdx].boundingBox)
            }
            assigned.insert(bestIdx)
        }
        return (groupA, groupB)
    }

    private static func quadraticSplitInternal(
        _ children: [(boundingBox: BoundingBox, node: RTreeNode<Element>)],
        maxEntries: Int
    ) -> (
        [(boundingBox: BoundingBox, node: RTreeNode<Element>)],
        [(boundingBox: BoundingBox, node: RTreeNode<Element>)]
    ) {
        let boxes = children.map(\.boundingBox)
        let (s1, s2) = pickSeeds(boxes)
        let minFill = max(maxEntries * 2 / 5, 2)
        var groupA = [children[s1]]
        var groupB = [children[s2]]
        var bbA = children[s1].boundingBox
        var bbB = children[s2].boundingBox
        var assigned = Set([s1, s2])

        for _ in 0..<children.count {
            if assigned.count == children.count { break }
            let remaining = children.count - assigned.count
            if groupA.count + remaining == minFill {
                for i in children.indices where !assigned.contains(i) { groupA.append(children[i]) }
                break
            }
            if groupB.count + remaining == minFill {
                for i in children.indices where !assigned.contains(i) { groupB.append(children[i]) }
                break
            }
            var bestIdx = -1
            var bestDiff = -Double.greatestFiniteMagnitude
            for i in children.indices where !assigned.contains(i) {
                let dA = bbA.union(children[i].boundingBox).area - bbA.area
                let dB = bbB.union(children[i].boundingBox).area - bbB.area
                let diff = abs(dA - dB)
                if diff > bestDiff {
                    bestDiff = diff
                    bestIdx = i
                }
            }
            guard bestIdx >= 0 else { break }
            let dA = bbA.union(children[bestIdx].boundingBox).area - bbA.area
            let dB = bbB.union(children[bestIdx].boundingBox).area - bbB.area
            if dA < dB || (dA == dB && bbA.area <= bbB.area) {
                groupA.append(children[bestIdx])
                bbA = bbA.union(children[bestIdx].boundingBox)
            } else {
                groupB.append(children[bestIdx])
                bbB = bbB.union(children[bestIdx].boundingBox)
            }
            assigned.insert(bestIdx)
        }
        return (groupA, groupB)
    }

    private static func pickSeeds(_ boxes: [BoundingBox]) -> (Int, Int) {
        var worstWaste = -Double.greatestFiniteMagnitude
        var seed1 = 0
        var seed2 = 1
        for i in 0..<boxes.count {
            for j in (i + 1)..<boxes.count {
                let combined = boxes[i].union(boxes[j])
                let waste = combined.area - boxes[i].area - boxes[j].area
                if waste > worstWaste {
                    worstWaste = waste
                    seed1 = i
                    seed2 = j
                }
            }
        }
        return (seed1, seed2)
    }

    // MARK: - Remove Internals

    /// Returns the modified node, or nil if the element was not found.
    /// Orphaned entries from underflowing nodes are collected for reinsertion.
    private static func removeFromNode(
        _ element: Element,
        node: RTreeNode<Element>,
        minEntries: Int,
        orphans: inout [RTreeEntry<Element>]
    ) -> RTreeNode<Element>? {
        switch node {
        case .leaf(var entries):
            guard let idx = entries.firstIndex(where: { $0.element == element }) else {
                return nil // not found
            }
            entries.remove(at: idx)
            if entries.isEmpty {
                return .leaf(entries: []) // will be cleaned up by parent
            }
            return .leaf(entries: entries)

        case .internal(var children):
            for i in children.indices {
                if let updated = removeFromNode(element, node: children[i].node, minEntries: minEntries, orphans: &orphans) {
                    // Check if updated child underflows
                    let underflows: Bool
                    switch updated {
                    case .leaf(let entries):
                        underflows = entries.isEmpty
                    case .internal(let grandchildren):
                        underflows = grandchildren.isEmpty
                    }

                    if underflows {
                        // Remove this child entirely; its remaining entries are already empty
                        children.remove(at: i)
                    } else {
                        // Check for underflow that requires orphan collection
                        let needsReinsert: Bool
                        switch updated {
                        case .leaf(let entries):
                            needsReinsert = entries.count < minEntries
                        case .internal(let grandchildren):
                            needsReinsert = grandchildren.count < minEntries
                        }

                        if needsReinsert {
                            // Collect all entries from this subtree as orphans
                            collectEntries(from: updated, into: &orphans)
                            children.remove(at: i)
                        } else {
                            children[i] = (boundingBox: updated.boundingBox, node: updated)
                        }
                    }

                    if children.isEmpty {
                        return .internal(children: [])
                    }
                    return .internal(children: children)
                }
            }
            return nil // not found in any child
        }
    }

    private static func collectEntries(from node: RTreeNode<Element>, into entries: inout [RTreeEntry<Element>]) {
        switch node {
        case .leaf(let leafEntries):
            entries.append(contentsOf: leafEntries)
        case .internal(let children):
            for child in children {
                collectEntries(from: child.node, into: &entries)
            }
        }
    }

    // MARK: - Search Internals

    private static func searchNode(
        _ node: RTreeNode<Element>,
        box: BoundingBox,
        results: inout [RTreeEntry<Element>]
    ) {
        switch node {
        case .leaf(let entries):
            for entry in entries {
                if entry.boundingBox.intersects(box) {
                    results.append(entry)
                }
            }
        case .internal(let children):
            for child in children {
                if child.boundingBox.intersects(box) {
                    searchNode(child.node, box: box, results: &results)
                }
            }
        }
    }

    // MARK: - Nearest Neighbor Internals

    private static func nearestInNode(
        _ node: RTreeNode<Element>,
        point: GeoCoordinate,
        bestDistSq: inout Double,
        bestEntry: inout RTreeEntry<Element>?
    ) {
        switch node {
        case .leaf(let entries):
            for entry in entries {
                let d = minDistSq(from: point, to: entry.boundingBox)
                if d < bestDistSq {
                    bestDistSq = d
                    bestEntry = entry
                }
            }
        case .internal(let children):
            // Sort children by min distance for branch-and-bound pruning
            let sorted = children
                .map { (minDist: minDistSq(from: point, to: $0.boundingBox), child: $0) }
                .sorted { $0.minDist < $1.minDist }
            for item in sorted {
                if item.minDist >= bestDistSq { break } // prune
                nearestInNode(item.child.node, point: point, bestDistSq: &bestDistSq, bestEntry: &bestEntry)
            }
        }
    }

    private static func minDistSq(from point: GeoCoordinate, to box: BoundingBox) -> Double {
        let dx: Double
        if point.latitude < box.minLatitude {
            dx = box.minLatitude - point.latitude
        } else if point.latitude > box.maxLatitude {
            dx = point.latitude - box.maxLatitude
        } else {
            dx = 0
        }
        let dy: Double
        if point.longitude < box.minLongitude {
            dy = box.minLongitude - point.longitude
        } else if point.longitude > box.maxLongitude {
            dy = point.longitude - box.maxLongitude
        } else {
            dy = 0
        }
        return dx * dx + dy * dy
    }

    // MARK: - Bulk Load (Sort-Tile-Recursive)

    private static func buildSTR(
        _ entries: [RTreeEntry<Element>],
        maxEntries: Int
    ) -> RTreeNode<Element> {
        if entries.count <= maxEntries {
            return .leaf(entries: entries)
        }

        // Build leaf nodes using STR packing
        let numLeaves = (entries.count + maxEntries - 1) / maxEntries
        let numSlabs = Int(ceil(sqrt(Double(numLeaves))))
        let slabSize = numSlabs * maxEntries

        // Sort by longitude center
        let sortedByLon = entries.sorted {
            ($0.boundingBox.minLongitude + $0.boundingBox.maxLongitude)
                < ($1.boundingBox.minLongitude + $1.boundingBox.maxLongitude)
        }

        var leafNodes: [RTreeNode<Element>] = []

        // Partition into vertical slabs, sort each by latitude, pack into leaves
        var offset = 0
        while offset < sortedByLon.count {
            let slabEnd = min(offset + slabSize, sortedByLon.count)
            let slab = Array(sortedByLon[offset..<slabEnd])

            // Sort slab by latitude center
            let sortedByLat = slab.sorted {
                ($0.boundingBox.minLatitude + $0.boundingBox.maxLatitude)
                    < ($1.boundingBox.minLatitude + $1.boundingBox.maxLatitude)
            }

            // Pack into leaf nodes
            var leafOffset = 0
            while leafOffset < sortedByLat.count {
                let leafEnd = min(leafOffset + maxEntries, sortedByLat.count)
                let leafEntries = Array(sortedByLat[leafOffset..<leafEnd])
                leafNodes.append(.leaf(entries: leafEntries))
                leafOffset = leafEnd
            }
            offset = slabEnd
        }

        // Recursively build internal nodes bottom-up
        return buildInternalLevel(leafNodes, maxEntries: maxEntries)
    }

    private static func buildInternalLevel(
        _ nodes: [RTreeNode<Element>],
        maxEntries: Int
    ) -> RTreeNode<Element> {
        if nodes.count == 1 { return nodes[0] }

        if nodes.count <= maxEntries {
            let children = nodes.map { (boundingBox: $0.boundingBox, node: $0) }
            return .internal(children: children)
        }

        // Group nodes into parent nodes of up to maxEntries children each
        var parentNodes: [RTreeNode<Element>] = []
        var offset = 0
        while offset < nodes.count {
            let end = min(offset + maxEntries, nodes.count)
            let group = Array(nodes[offset..<end])
            let children = group.map { (boundingBox: $0.boundingBox, node: $0) }
            parentNodes.append(.internal(children: children))
            offset = end
        }

        return buildInternalLevel(parentNodes, maxEntries: maxEntries)
    }
}
