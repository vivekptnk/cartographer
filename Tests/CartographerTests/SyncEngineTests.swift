import XCTest
import struct Cartographer.Operation
@testable import Cartographer

// MARK: - Mock Transport

private final class MockTransport: SyncTransport, @unchecked Sendable {
    var pushError: SyncError?
    var pullError: SyncError?
    var pullOps: [Operation] = []
    var pullToken: SyncToken = SyncToken(data: Data())
    var pushCallCount = 0
    var pullCallCount = 0
    var failPushUntilAttempt: Int = 0 // fail with pushError until this attempt number
    var orderLog: [String] = []
    var lastReceivedPullToken: SyncToken?

    func push(operations: [Operation]) async throws {
        pushCallCount += 1
        orderLog.append("push")
        if let err = pushError {
            if failPushUntilAttempt > 0 && pushCallCount >= failPushUntilAttempt {
                // succeed now
            } else {
                throw err
            }
        }
    }

    func pull(since token: SyncToken?) async throws -> ([Operation], SyncToken) {
        pullCallCount += 1
        orderLog.append("pull")
        lastReceivedPullToken = token
        if let err = pullError {
            throw err
        }
        return (pullOps, pullToken)
    }
}

// MARK: - Helpers

private func makeOp(synced: Bool = false) -> Operation {
    Operation(
        type: .insert,
        entityType: .annotation,
        entityID: UUID(),
        projectID: UUID(),
        hlc: HLCTimestamp(physicalTime: UInt64(Date().timeIntervalSince1970 * 1000), logicalCounter: 0, nodeID: UUID()),
        payload: Data("{}".utf8),
        synced: synced
    )
}

private func makeToken(_ value: String = "tok") -> SyncToken {
    SyncToken(data: Data(value.utf8))
}

// MARK: - Tests

final class SyncEngineTests: XCTestCase {

    private func makeEngine(transport: MockTransport) throws -> SyncEngine {
        let log = try OperationLog(path: ":memory:")
        return SyncEngine(transport: transport, operationLog: log)
    }

    // MARK: - Push State Transitions

    func testPush_EmptyOperations_RemainsIdle() async throws {
        let transport = MockTransport()
        let engine = try makeEngine(transport: transport)

        try await engine.push(operations: [])

        let state = await engine.state
        XCTAssertEqual(transport.pushCallCount, 0, "Should not call transport for empty operations")
        if case .idle = state { } else {
            XCTFail("Expected idle state, got \(state)")
        }
    }

    func testPush_Success_TransitionsToIdle() async throws {
        let transport = MockTransport()
        let engine = try makeEngine(transport: transport)

        try await engine.push(operations: [makeOp()])

        let state = await engine.state
        if case .idle = state { } else {
            XCTFail("Expected idle state after successful push, got \(state)")
        }
        XCTAssertEqual(transport.pushCallCount, 1)
    }

    func testPush_TransportError_TransitionsToError() async throws {
        let transport = MockTransport()
        transport.pushError = .authenticationFailed
        let engine = try makeEngine(transport: transport)

        do {
            try await engine.push(operations: [makeOp()])
            XCTFail("Expected push to throw")
        } catch {
            let state = await engine.state
            if case .error(let syncError) = state {
                if case .authenticationFailed = syncError { } else {
                    XCTFail("Expected authenticationFailed, got \(syncError)")
                }
            } else {
                XCTFail("Expected error state, got \(state)")
            }
        }
    }

    func testPush_TransientError_Retries() async throws {
        let transport = MockTransport()
        transport.pushError = .networkUnavailable
        transport.failPushUntilAttempt = 3 // fail attempts 1,2; succeed on 3
        let engine = try makeEngine(transport: transport)

        try await engine.push(operations: [makeOp()])

        let state = await engine.state
        if case .idle = state { } else {
            XCTFail("Expected idle state after transient retries, got \(state)")
        }
        XCTAssertEqual(transport.pushCallCount, 3, "Should retry transient errors")
    }

    func testPush_NonTransientError_NoRetry() async throws {
        let transport = MockTransport()
        transport.pushError = .quotaExceeded
        let engine = try makeEngine(transport: transport)

        do {
            try await engine.push(operations: [makeOp()])
            XCTFail("Expected push to throw")
        } catch {
            XCTAssertEqual(transport.pushCallCount, 1, "Should not retry non-transient errors")
        }
    }

    // MARK: - Pull State Transitions

    func testPull_Success_TransitionsToIdle() async throws {
        let transport = MockTransport()
        transport.pullToken = makeToken()
        let engine = try makeEngine(transport: transport)

        let ops = try await engine.pull()

        let state = await engine.state
        if case .idle = state { } else {
            XCTFail("Expected idle state after successful pull, got \(state)")
        }
        XCTAssertTrue(ops.isEmpty)
        XCTAssertEqual(transport.pullCallCount, 1)
    }

    func testPull_ReturnsRemoteOperations() async throws {
        let transport = MockTransport()
        transport.pullOps = [makeOp(synced: true), makeOp(synced: true)]
        transport.pullToken = makeToken()
        let engine = try makeEngine(transport: transport)

        let ops = try await engine.pull()

        XCTAssertEqual(ops.count, 2, "Should return remote operations")
    }

    func testPull_UpdatesSyncToken() async throws {
        let transport = MockTransport()
        let token1 = makeToken("first")
        transport.pullToken = token1
        let engine = try makeEngine(transport: transport)

        // First pull — no token
        _ = try await engine.pull()
        XCTAssertNil(transport.lastReceivedPullToken, "First pull should have nil token")

        // Second pull — should use token from first pull
        let token2 = makeToken("second")
        transport.pullToken = token2
        _ = try await engine.pull()
        XCTAssertEqual(transport.lastReceivedPullToken?.data, token1.data,
                       "Second pull should use token from first pull")
    }

    func testPull_TransportError_TransitionsToError() async throws {
        let transport = MockTransport()
        transport.pullError = .zoneNotFound("test")
        let engine = try makeEngine(transport: transport)

        do {
            _ = try await engine.pull()
            XCTFail("Expected pull to throw")
        } catch {
            let state = await engine.state
            if case .error = state { } else {
                XCTFail("Expected error state, got \(state)")
            }
        }
    }

    // MARK: - Full Sync Cycle

    func testSync_PushesThenPulls() async throws {
        let transport = MockTransport()
        transport.pullToken = makeToken()
        let engine = try makeEngine(transport: transport)

        _ = try await engine.sync(localUnsynced: [makeOp()])

        XCTAssertEqual(transport.orderLog, ["push", "pull"], "Sync must push before pull")
    }

    func testSync_ReturnsRemoteOps() async throws {
        let transport = MockTransport()
        transport.pullOps = [makeOp(synced: true)]
        transport.pullToken = makeToken()
        let engine = try makeEngine(transport: transport)

        let result = try await engine.sync(localUnsynced: [makeOp()])

        XCTAssertEqual(result.count, 1, "Sync should return remote operations for local merge")
    }

    func testSync_PushFails_DoesNotPull() async throws {
        let transport = MockTransport()
        transport.pushError = .authenticationFailed
        let engine = try makeEngine(transport: transport)

        do {
            _ = try await engine.sync(localUnsynced: [makeOp()])
            XCTFail("Expected sync to throw")
        } catch {
            XCTAssertEqual(transport.pullCallCount, 0, "Should not pull if push fails")
        }
    }

    func testSync_EmptyUnsynced_StillPulls() async throws {
        let transport = MockTransport()
        transport.pullOps = [makeOp(synced: true)]
        transport.pullToken = makeToken()
        let engine = try makeEngine(transport: transport)

        let result = try await engine.sync(localUnsynced: [])

        XCTAssertEqual(result.count, 1, "Should pull even with no local operations to push")
        XCTAssertEqual(transport.pushCallCount, 0, "Should skip push for empty operations")
    }
}
