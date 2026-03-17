// MARK: - Cartographer
// Public entry point for the Cartographer library.
// This file re-exports the key types that consumers interact with.

/// Cartographer: An offline-first collaborative map annotation engine.
///
/// ## Quick Start
/// ```swift
/// // Create a project
/// let cartographer = Cartographer(nodeID: UUID())
///
/// // Add an annotation
/// let annotation = await cartographer.createAnnotation(
///     type: .pin,
///     coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
///     title: "NYC Office",
///     projectID: projectID
/// )
///
/// // Query visible annotations
/// let visible = cartographer.annotations(in: mapBoundingBox)
///
/// // Sync when online
/// let remoteOps = try await cartographer.sync()
/// ```
public struct Cartographer: Sendable {
    public let nodeID: EntityID
    // Components will be wired here as they're implemented

    public init(nodeID: EntityID = EntityID()) {
        self.nodeID = nodeID
    }
}
