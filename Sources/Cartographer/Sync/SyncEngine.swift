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
    private let operationLog: OperationLog
    private var lastSyncToken: SyncToken?
    private(set) public var state: SyncState = .idle

    /// Maximum retry attempts for transient errors.
    private static let maxRetries = 3

    public init(transport: any SyncTransport, operationLog: OperationLog) {
        self.transport = transport
        self.operationLog = operationLog
    }

    /// Push all unsynced local operations to the remote.
    public func push(operations: [Operation]) async throws {
        guard !operations.isEmpty else { return }

        state = .pushing
        do {
            try await retryOnTransient {
                try await self.transport.push(operations: operations)
            }
            try await operationLog.markSynced(operationIDs: operations.map(\.id))
            state = .idle
        } catch {
            state = .error(asSyncError(error))
            throw error
        }
    }

    /// Pull remote operations since last sync token.
    public func pull() async throws -> [Operation] {
        state = .pulling
        do {
            let (operations, newToken) = try await retryOnTransient {
                try await self.transport.pull(since: self.lastSyncToken)
            }
            lastSyncToken = newToken
            state = .idle
            return operations
        } catch {
            state = .error(asSyncError(error))
            throw error
        }
    }

    /// Full sync cycle: push local, pull remote.
    /// Target: < 500ms for 100 operations (excluding network latency).
    public func sync(localUnsynced: [Operation]) async throws -> [Operation] {
        try await push(operations: localUnsynced)
        return try await pull()
    }

    // MARK: - Private

    /// Retry a throwing async closure with exponential backoff on transient SyncErrors.
    private func retryOnTransient<T>(
        _ work: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<Self.maxRetries {
            do {
                return try await work()
            } catch let error as SyncError where error.isTransient {
                lastError = error
                let delayMs = UInt64(pow(2.0, Double(attempt))) * 100_000_000 // 100ms, 200ms, 400ms
                try await Task.sleep(nanoseconds: delayMs)
            }
        }
        throw lastError!
    }

    /// Map arbitrary errors to SyncError.
    private func asSyncError(_ error: Error) -> SyncError {
        if let syncError = error as? SyncError {
            return syncError
        }
        return .serverError(error.localizedDescription)
    }
}

// MARK: - SyncError Transient Classification

extension SyncError {
    /// Whether this error is transient and worth retrying.
    var isTransient: Bool {
        switch self {
        case .networkUnavailable, .serverError:
            return true
        case .authenticationFailed, .quotaExceeded, .zoneNotFound:
            return false
        }
    }
}
