// MARK: - Observed-Remove Set (OR-Set)
// Add-wins semantics: concurrent add + remove → element exists.
// Each add is tagged with a unique HLC. Remove only removes observed tags.

import Foundation

/// An Observed-Remove Set with add-wins semantics.
public struct ORSet<Element: Hashable & Sendable & Codable>: Sendable, Codable {
    /// Each element maps to the set of HLC tags that added it.
    public private(set) var entries: [Element: Set<HLCTimestamp>]
    /// Tombstones: tags that have been removed.
    public private(set) var tombstones: Set<HLCTimestamp>

    public init() {
        self.entries = [:]
        self.tombstones = []
    }

    /// All elements currently in the set (have at least one non-tombstoned tag).
    public var elements: Set<Element> {
        var result = Set<Element>()
        for (element, tags) in entries {
            let liveTags = tags.subtracting(tombstones)
            if !liveTags.isEmpty {
                result.insert(element)
            }
        }
        return result
    }

    /// Check if an element is in the set.
    public func contains(_ element: Element) -> Bool {
        guard let tags = entries[element] else { return false }
        return !tags.subtracting(tombstones).isEmpty
    }

    /// Add an element with a unique tag.
    public mutating func add(_ element: Element, tag: HLCTimestamp) {
        entries[element, default: []].insert(tag)
    }

    /// Remove an element by tombstoning all currently observed tags.
    public mutating func remove(_ element: Element) {
        guard let tags = entries[element] else { return }
        tombstones.formUnion(tags)
    }

    /// Merge with a remote OR-Set.
    /// Union of all entries, union of all tombstones.
    public mutating func merge(_ remote: ORSet<Element>) {
        for (element, remoteTags) in remote.entries {
            entries[element, default: []].formUnion(remoteTags)
        }
        tombstones.formUnion(remote.tombstones)
    }

    /// Non-mutating merge.
    public func merged(with remote: ORSet<Element>) -> ORSet<Element> {
        var result = self
        result.merge(remote)
        return result
    }

    /// Number of live elements.
    public var count: Int { elements.count }

    /// Whether the set is empty.
    public var isEmpty: Bool { elements.isEmpty }
}
