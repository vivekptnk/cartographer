// MARK: - Sync Engine
// Manages the push/pull state machine for syncing operations via CloudKit.
// CRDTs make conflict resolution a non-issue — we just merge operation sets.

import Foundation

/// Sync state for tracking what has been synced.
public enum SyncState: Sendable {
    case idle
    case pushing
    case pulling
    case error(SyncError)
}

/// Orchestrates bidirectional sync of CRDT operations.
public actor SyncEngine {
    private let transport: any SyncTransport
    private var lastSyncToken: SyncToken?
    private(set) public var state: SyncState = .idle

    public init(transport: any SyncTransport) {
        self.transport = transport
    }

    /// Push all unsynced local operations to the remote.
    public func push(operations: [Operation]) async throws {
        // TODO: Implement for CG-011
        // 1. Set state = .pushing
        // 2. Batch operations into CKRecord arrays
        // 3. Push via transport
        // 4. Mark operations as synced in local DB
        // 5. Set state = .idle
        // Error handling: exponential backoff on transient errors
        fatalError("Not yet implemented — implement for CG-011")
    }

    /// Pull remote operations since last sync token.
    public func pull() async throws -> [Operation] {
        // TODO: Implement for CG-011
        // 1. Set state = .pulling
        // 2. Fetch via transport with lastSyncToken
        // 3. Update lastSyncToken
        // 4. Return new operations (caller will append to local log + re-materialize)
        // 5. Set state = .idle
        fatalError("Not yet implemented — implement for CG-011")
    }

    /// Full sync cycle: push local, pull remote.
    /// Target: < 500ms for 100 operations (excluding network latency).
    public func sync(localUnsynced: [Operation]) async throws -> [Operation] {
        // TODO: Implement for CG-011
        // 1. Push unsynced
        // 2. Pull remote
        // 3. Return remote operations for local merge
        fatalError("Not yet implemented — implement for CG-011")
    }
}
