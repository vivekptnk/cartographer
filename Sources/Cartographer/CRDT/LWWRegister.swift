// MARK: - Last-Writer-Wins Register
// Each register holds a value and the HLC timestamp of when it was set.
// Merge always keeps the value with the higher timestamp.
// Properties: commutative, associative, idempotent.

import Foundation

/// A Last-Writer-Wins Register holding a value tagged with an HLC timestamp.
public struct LWWRegister<Value: Sendable & Codable & Equatable>: Sendable, Codable where Value: Hashable {
    public private(set) var value: Value
    public private(set) var timestamp: HLCTimestamp

    public init(value: Value, timestamp: HLCTimestamp) {
        self.value = value
        self.timestamp = timestamp
    }

    /// Update the value only if the new timestamp is strictly greater.
    @discardableResult
    public mutating func set(_ newValue: Value, at newTimestamp: HLCTimestamp) -> Bool {
        if newTimestamp > timestamp {
            value = newValue
            timestamp = newTimestamp
            return true
        }
        return false
    }

    /// Merge with a remote register. Keeps the value with the higher timestamp.
    public mutating func merge(_ remote: LWWRegister<Value>) {
        if remote.timestamp > timestamp {
            value = remote.value
            timestamp = remote.timestamp
        }
    }

    /// Non-mutating merge that returns a new register.
    public func merged(with remote: LWWRegister<Value>) -> LWWRegister<Value> {
        remote.timestamp > timestamp ? remote : self
    }
}
