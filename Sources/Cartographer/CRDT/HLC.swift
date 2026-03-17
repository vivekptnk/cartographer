// MARK: - Hybrid Logical Clock
// Reference: "Logical Physical Clocks and Consistent Snapshots" — Kulkarni et al.
//
// HLC = (physical_time, logical_counter, node_id)
// Guarantees: every tick() > previous tick, merge() ≥ max(local, remote)

import Foundation

/// A single HLC timestamp. Comparable, Sendable, and binary-encodable.
public struct HLCTimestamp: Sendable, Codable, Hashable, Comparable {
    /// Wall clock component (milliseconds since epoch).
    public let physicalTime: UInt64
    /// Logical counter for ordering events at the same physical time.
    public let logicalCounter: UInt16
    /// Unique identifier for the originating node/device.
    public let nodeID: UUID

    public init(physicalTime: UInt64, logicalCounter: UInt16, nodeID: UUID) {
        self.physicalTime = physicalTime
        self.logicalCounter = logicalCounter
        self.nodeID = nodeID
    }

    public static func < (lhs: HLCTimestamp, rhs: HLCTimestamp) -> Bool {
        if lhs.physicalTime != rhs.physicalTime {
            return lhs.physicalTime < rhs.physicalTime
        }
        if lhs.logicalCounter != rhs.logicalCounter {
            return lhs.logicalCounter < rhs.logicalCounter
        }
        return lhs.nodeID.uuidString < rhs.nodeID.uuidString
    }

    /// 16-byte compact binary encoding: 8 bytes physical + 2 bytes counter + 6 bytes node prefix.
    public var binaryEncoding: Data {
        var data = Data(capacity: 16)
        var pt = physicalTime.bigEndian
        data.append(Data(bytes: &pt, count: 8))
        var lc = logicalCounter.bigEndian
        data.append(Data(bytes: &lc, count: 2))
        let uuidBytes = withUnsafeBytes(of: nodeID.uuid) { Array($0) }
        data.append(contentsOf: uuidBytes.prefix(6))
        return data
    }

    /// Decode from 16-byte binary.
    public static func fromBinary(_ data: Data) -> HLCTimestamp? {
        guard data.count == 16 else { return nil }
        let pt = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt64.self).bigEndian }
        let lc = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt16.self).bigEndian }
        // Reconstruct UUID with 6-byte prefix + zeros
        var uuidBytes: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &uuidBytes) { buf in
            for i in 0..<6 { buf[i] = data[10 + i] }
        }
        return HLCTimestamp(physicalTime: pt, logicalCounter: lc, nodeID: UUID(uuid: uuidBytes))
    }
}

/// Thread-safe HLC clock. All access serialized through actor isolation.
public actor HLCClock {
    private var lastTimestamp: HLCTimestamp
    private let nodeID: UUID

    public init(nodeID: UUID = UUID()) {
        self.nodeID = nodeID
        self.lastTimestamp = HLCTimestamp(physicalTime: 0, logicalCounter: 0, nodeID: nodeID)
    }

    /// Generate a new timestamp guaranteed to be greater than the last.
    public func tick() -> HLCTimestamp {
        let now = Self.currentPhysicalTime()
        let newTimestamp: HLCTimestamp

        if now > lastTimestamp.physicalTime {
            newTimestamp = HLCTimestamp(physicalTime: now, logicalCounter: 0, nodeID: nodeID)
        } else {
            newTimestamp = HLCTimestamp(
                physicalTime: lastTimestamp.physicalTime,
                logicalCounter: lastTimestamp.logicalCounter + 1,
                nodeID: nodeID
            )
        }

        lastTimestamp = newTimestamp
        return newTimestamp
    }

    /// Merge with a remote timestamp. Returns a new timestamp ≥ max(local, remote).
    public func merge(remote: HLCTimestamp) -> HLCTimestamp {
        let now = Self.currentPhysicalTime()
        let maxPT = max(now, max(lastTimestamp.physicalTime, remote.physicalTime))
        let newTimestamp: HLCTimestamp

        if maxPT == now && now > lastTimestamp.physicalTime && now > remote.physicalTime {
            newTimestamp = HLCTimestamp(physicalTime: now, logicalCounter: 0, nodeID: nodeID)
        } else if maxPT == lastTimestamp.physicalTime && lastTimestamp.physicalTime == remote.physicalTime {
            newTimestamp = HLCTimestamp(
                physicalTime: maxPT,
                logicalCounter: max(lastTimestamp.logicalCounter, remote.logicalCounter) + 1,
                nodeID: nodeID
            )
        } else if maxPT == lastTimestamp.physicalTime {
            newTimestamp = HLCTimestamp(
                physicalTime: maxPT,
                logicalCounter: lastTimestamp.logicalCounter + 1,
                nodeID: nodeID
            )
        } else {
            // maxPT == remote.physicalTime
            newTimestamp = HLCTimestamp(
                physicalTime: maxPT,
                logicalCounter: remote.logicalCounter + 1,
                nodeID: nodeID
            )
        }

        lastTimestamp = newTimestamp
        return newTimestamp
    }

    /// Current physical time in milliseconds since epoch.
    private static func currentPhysicalTime() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}
