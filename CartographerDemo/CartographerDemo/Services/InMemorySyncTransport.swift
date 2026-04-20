import Foundation
import Cartographer

/// In-memory round-trip transport used by the demo when the CloudKit sync
/// toggle is ON but the host has no iCloud account. Keeps the `SyncEngine`
/// state machine exercised end-to-end (push → pull → materialize) without a
/// network dependency.
///
/// This is **not** a real transport — swap to the CloudKit-backed one in
/// `SyncEngine` for field testing. Kept colocated with the demo so the engine
/// target stays CloudKit-agnostic.
final class InMemorySyncTransport: SyncTransport, @unchecked Sendable {

    private let queue = DispatchQueue(label: "cartographer.demo.inmemory-sync")
    private var operations: [Cartographer.Operation] = []
    private var cursor: Int = 0

    func push(operations incoming: [Cartographer.Operation]) async throws {
        queue.sync {
            for op in incoming where !operations.contains(where: { $0.id == op.id }) {
                operations.append(op)
            }
        }
    }

    func pull(since token: SyncToken?) async throws -> ([Cartographer.Operation], SyncToken) {
        queue.sync {
            let start = Self.decode(token) ?? 0
            let slice = Array(operations[min(start, operations.count)..<operations.count])
            let newCursor = operations.count
            cursor = newCursor
            return (slice, Self.encode(newCursor))
        }
    }

    private static func encode(_ index: Int) -> SyncToken {
        var value = Int64(index).littleEndian
        let data = Data(bytes: &value, count: MemoryLayout<Int64>.size)
        return SyncToken(data: data)
    }

    private static func decode(_ token: SyncToken?) -> Int? {
        guard let data = token?.data, data.count == MemoryLayout<Int64>.size else { return nil }
        return data.withUnsafeBytes { ptr in
            Int(Int64(littleEndian: ptr.load(as: Int64.self)))
        }
    }
}
