// MARK: - Operation
// Every mutation in Cartographer is recorded as an Operation.
// Operations are the unit of sync. Replaying all operations produces the current state.

import Foundation

/// A single mutation in the operation log.
public struct Operation: Sendable, Codable, Identifiable, Hashable {
    public let id: EntityID
    public let type: OperationType
    public let entityType: EntityType
    public let entityID: EntityID
    public let projectID: EntityID
    public let hlc: HLCTimestamp
    /// JSON-encoded payload of the mutation (field values, etc).
    public let payload: Data
    /// Whether this operation has been synced to the remote.
    public var synced: Bool

    public init(
        id: EntityID = EntityID(),
        type: OperationType,
        entityType: EntityType,
        entityID: EntityID,
        projectID: EntityID,
        hlc: HLCTimestamp,
        payload: Data,
        synced: Bool = false
    ) {
        self.id = id
        self.type = type
        self.entityType = entityType
        self.entityID = entityID
        self.projectID = projectID
        self.hlc = hlc
        self.payload = payload
        self.synced = synced
    }
}
