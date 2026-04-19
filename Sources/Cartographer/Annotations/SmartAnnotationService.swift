// MARK: - SmartAnnotationService
//
// Public seam between Cartographer and on-device language models
// (TinyBrain, plus any future provider). The demo app and the library consume
// this protocol only; the real model wiring lives behind it in a downstream
// module so that the engine layer stays free of inference dependencies.
//
// See docs/INTEGRATION-TINYBRAIN.md for the TinyBrain contract and fallback
// rules.

import Foundation

// MARK: - Protocol

/// A service that performs language-model-assisted queries against a set of
/// annotations. Implementations may be offline-only, cloud-backed, or mock.
///
/// All methods must be safe to call from any actor context and must not block
/// the caller's thread. Implementations that load models are expected to lazy-
/// initialize on first use and surface failure through the thrown errors here.
public protocol SmartAnnotationService: Sendable {

    /// Return the IDs of annotations whose content is semantically relevant
    /// to `query`, ordered best-match-first.
    ///
    /// `corpus` is the candidate set the caller wants ranked. Implementations
    /// must not mutate or persist `corpus`.
    func search(query: String, in corpus: [Annotation]) async throws -> [EntityID]

    /// Return a short, human-readable summary of `annotations`.
    /// Used for route-summary cards and "what's in this region" explanations.
    func summarize(annotations: [Annotation]) async throws -> String
}

// MARK: - Errors

public enum SmartAnnotationServiceError: Error, Sendable {
    /// The implementation's backing model could not be loaded.
    case modelUnavailable(String)
    /// The query was empty, too long, or otherwise malformed.
    case invalidQuery(String)
    /// An underlying transport or inference call failed.
    case inferenceFailed(String)
}

// MARK: - Mock Implementation

/// Deterministic, offline, zero-dependency implementation of
/// `SmartAnnotationService`. Ships with the engine so the UI can be wired up
/// without a model loaded. TinyBrain replaces this at runtime in v0.3.0+.
///
/// - `search` scores each annotation by counting case-insensitive query-token
///   hits in the `title`, `body`, and `metadata` values, and returns matches
///   sorted by score (ties broken by most-recently-updated).
/// - `summarize` returns the project-scoped count of each annotation type plus
///   the first title in each group, joined with semicolons. It is intentionally
///   trivial so a reviewer can reason about it at a glance.
public struct MockSmartAnnotationService: SmartAnnotationService {

    public init() {}

    public func search(query: String, in corpus: [Annotation]) async throws -> [EntityID] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SmartAnnotationServiceError.invalidQuery("empty query") }

        let tokens = trimmed
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        struct Scored { let id: EntityID; let score: Int; let updatedAt: Date }
        var scored: [Scored] = []
        scored.reserveCapacity(corpus.count)

        for annotation in corpus {
            let haystack = (
                [annotation.title, annotation.body]
                + annotation.metadata.values
            )
                .joined(separator: "\n")
                .lowercased()
            guard !haystack.isEmpty else { continue }

            var score = 0
            for token in tokens {
                // Sum of non-overlapping occurrences of each token.
                if token.isEmpty { continue }
                var remainder = Substring(haystack)
                while let range = remainder.range(of: token) {
                    score += 1
                    remainder = remainder[range.upperBound...]
                }
            }
            if score > 0 {
                scored.append(Scored(id: annotation.id, score: score, updatedAt: annotation.updatedAt))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.updatedAt > rhs.updatedAt
        }
        return scored.map { $0.id }
    }

    public func summarize(annotations: [Annotation]) async throws -> String {
        guard !annotations.isEmpty else { return "No annotations." }

        var buckets: [AnnotationType: [Annotation]] = [:]
        for a in annotations {
            buckets[a.type, default: []].append(a)
        }

        // Stable order: pin → note → route → polygon.
        let order: [AnnotationType] = [.pin, .note, .route, .polygon]
        let parts: [String] = order.compactMap { type in
            guard let items = buckets[type], !items.isEmpty else { return nil }
            let sample = items.first(where: { !$0.title.isEmpty })?.title
            let label = pluralLabel(type: type, count: items.count)
            if let sample {
                return "\(items.count) \(label) (e.g. \(sample))"
            }
            return "\(items.count) \(label)"
        }
        return parts.joined(separator: "; ")
    }

    private func pluralLabel(type: AnnotationType, count: Int) -> String {
        switch type {
        case .pin:     return count == 1 ? "pin"     : "pins"
        case .note:    return count == 1 ? "note"    : "notes"
        case .route:   return count == 1 ? "route"   : "routes"
        case .polygon: return count == 1 ? "polygon" : "polygons"
        }
    }
}
