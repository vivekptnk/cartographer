// MARK: - CRDT Harness Tests
// This harness defines the complete behavioral contract for HLC, LWW-Register, and OR-Set.
// RULE: Never modify this file to make tests pass. Fix the implementation instead.

import XCTest
@testable import Cartographer

final class CRDTHarnessTests: XCTestCase {

    // MARK: - HLC Tests

    func testHLC_TickMonotonicallyIncreasing() async {
        let clock = HLCClock(nodeID: UUID())
        var previous = await clock.tick()
        for _ in 0..<1000 {
            let current = await clock.tick()
            XCTAssertGreaterThan(current, previous, "Each tick must be strictly greater than the previous")
            previous = current
        }
    }

    func testHLC_TicksAtSamePhysicalTime_IncrementLogical() async {
        let clock = HLCClock(nodeID: UUID())
        let t1 = await clock.tick()
        let t2 = await clock.tick()
        // If both happen within the same millisecond, logical counter must differ
        if t1.physicalTime == t2.physicalTime {
            XCTAssertGreaterThan(t2.logicalCounter, t1.logicalCounter)
        }
    }

    func testHLC_MergeWithFutureClock_Advances() async {
        let nodeA = UUID()
        let nodeB = UUID()
        let clockA = HLCClock(nodeID: nodeA)

        let futureTime = UInt64(Date().timeIntervalSince1970 * 1000) + 60_000 // 1 min in future
        let remoteTimestamp = HLCTimestamp(physicalTime: futureTime, logicalCounter: 5, nodeID: nodeB)

        let beforeMerge = await clockA.tick()
        let afterMerge = await clockA.merge(remote: remoteTimestamp)

        XCTAssertGreaterThan(afterMerge, beforeMerge, "Merge with future clock must advance")
        XCTAssertGreaterThan(afterMerge, remoteTimestamp, "Merged timestamp must be > remote")
    }

    func testHLC_MergeWithPastClock_NoRegression() async {
        let clockA = HLCClock(nodeID: UUID())

        let current = await clockA.tick()
        let pastTimestamp = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: UUID())

        let afterMerge = await clockA.merge(remote: pastTimestamp)
        XCTAssertGreaterThan(afterMerge, current, "Merge with past clock must not regress")
    }

    func testHLC_BinaryEncodingRoundTrip() {
        let original = HLCTimestamp(
            physicalTime: 1_700_000_000_000,
            logicalCounter: 42,
            nodeID: UUID()
        )
        let encoded = original.binaryEncoding
        XCTAssertEqual(encoded.count, 16, "Binary encoding must be exactly 16 bytes")

        let decoded = HLCTimestamp.fromBinary(encoded)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.physicalTime, original.physicalTime)
        XCTAssertEqual(decoded?.logicalCounter, original.logicalCounter)
    }

    func testHLC_ComparisonDeterministic() {
        let nodeA = UUID()
        let nodeB = UUID()
        let t1 = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: nodeA)
        let t2 = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: nodeB)
        // Same physical + logical → node ID breaks tie deterministically
        XCTAssertNotEqual(t1, t2)
        XCTAssertTrue(t1 < t2 || t2 < t1, "Total ordering must exist")
    }

    // MARK: - LWW-Register Tests

    func testLWW_HigherTimestampWins() {
        let node = UUID()
        let low = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: node)
        let high = HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: node)

        var register = LWWRegister(value: "old", timestamp: low)
        register.set("new", at: high)
        XCTAssertEqual(register.value, "new")
    }

    func testLWW_LowerTimestampRejected() {
        let node = UUID()
        let low = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: node)
        let high = HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: node)

        var register = LWWRegister(value: "current", timestamp: high)
        let updated = register.set("stale", at: low)
        XCTAssertFalse(updated)
        XCTAssertEqual(register.value, "current", "Lower timestamp must not overwrite")
    }

    func testLWW_MergeCommutative() {
        let node = UUID()
        let t1 = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: node)
        let t2 = HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: node)

        let regA = LWWRegister(value: "A", timestamp: t1)
        let regB = LWWRegister(value: "B", timestamp: t2)

        let mergedAB = regA.merged(with: regB)
        let mergedBA = regB.merged(with: regA)

        XCTAssertEqual(mergedAB.value, mergedBA.value, "Merge must be commutative")
        XCTAssertEqual(mergedAB.timestamp, mergedBA.timestamp)
    }

    func testLWW_MergeIdempotent() {
        let node = UUID()
        let t1 = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: node)

        let reg = LWWRegister(value: "same", timestamp: t1)
        let merged = reg.merged(with: reg)

        XCTAssertEqual(merged.value, reg.value, "Merge with self must be idempotent")
        XCTAssertEqual(merged.timestamp, reg.timestamp)
    }

    func testLWW_MergeAssociative() {
        let node = UUID()
        let t1 = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: node)
        let t2 = HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: node)
        let t3 = HLCTimestamp(physicalTime: 3000, logicalCounter: 0, nodeID: node)

        let a = LWWRegister(value: "A", timestamp: t1)
        let b = LWWRegister(value: "B", timestamp: t2)
        let c = LWWRegister(value: "C", timestamp: t3)

        let leftFirst = a.merged(with: b).merged(with: c)
        let rightFirst = a.merged(with: b.merged(with: c))

        XCTAssertEqual(leftFirst.value, rightFirst.value, "Merge must be associative")
        XCTAssertEqual(leftFirst.timestamp, rightFirst.timestamp)
    }

    func testLWW_ConcurrentEdits_DifferentFields() {
        let nodeA = UUID()
        let nodeB = UUID()
        let tA = HLCTimestamp(physicalTime: 1000, logicalCounter: 5, nodeID: nodeA)
        let tB = HLCTimestamp(physicalTime: 1000, logicalCounter: 3, nodeID: nodeB)

        // Simulate two devices editing different fields concurrently
        var titleA = LWWRegister(value: "Title from A", timestamp: tA)
        var bodyB = LWWRegister(value: "Body from B", timestamp: tB)

        // Remote updates arrive
        let remoteTitleB = LWWRegister(value: "Title from B", timestamp: tB)
        let remoteBodyA = LWWRegister(value: "Body from A", timestamp: tA)

        titleA.merge(remoteTitleB)
        bodyB.merge(remoteBodyA)

        // Both fields should resolve deterministically
        XCTAssertEqual(titleA.value, "Title from A", "Higher logical counter wins")
        XCTAssertEqual(bodyB.value, "Body from A", "Higher logical counter wins")
    }

    // MARK: - OR-Set Tests

    func testORSet_AddContains() {
        let node = UUID()
        var set = ORSet<String>()
        let tag = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: node)

        set.add("hello", tag: tag)
        XCTAssertTrue(set.contains("hello"))
        XCTAssertEqual(set.count, 1)
    }

    func testORSet_RemoveRemoves() {
        let node = UUID()
        var set = ORSet<String>()
        let tag = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: node)

        set.add("hello", tag: tag)
        set.remove("hello")
        XCTAssertFalse(set.contains("hello"))
        XCTAssertEqual(set.count, 0)
    }

    func testORSet_ConcurrentAddRemove_AddWins() {
        let nodeA = UUID()
        let nodeB = UUID()
        let tagA = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: nodeA)
        let tagB = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: nodeB)

        // Device A adds "item" with tagA
        var setA = ORSet<String>()
        setA.add("item", tag: tagA)

        // Device B independently adds "item" with tagB, then removes it
        var setB = ORSet<String>()
        setB.add("item", tag: tagB)
        setB.remove("item")
        // setB now has "item" tombstoned with tagB

        // Merge: setA's tagA was never seen by setB's remove → add wins
        var merged = setA
        merged.merge(setB)
        XCTAssertTrue(merged.contains("item"), "Concurrent add must win over concurrent remove")
    }

    func testORSet_SequentialAddRemoveAdd() {
        let node = UUID()
        var set = ORSet<String>()

        let tag1 = HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: node)
        set.add("item", tag: tag1)
        set.remove("item")

        // Re-add with new tag
        let tag2 = HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: node)
        set.add("item", tag: tag2)

        XCTAssertTrue(set.contains("item"), "Re-add after remove must work")
    }

    func testORSet_MergeCommutative() {
        let nodeA = UUID()
        let nodeB = UUID()

        var setA = ORSet<String>()
        setA.add("x", tag: HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: nodeA))
        setA.add("y", tag: HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: nodeA))

        var setB = ORSet<String>()
        setB.add("y", tag: HLCTimestamp(physicalTime: 1500, logicalCounter: 0, nodeID: nodeB))
        setB.add("z", tag: HLCTimestamp(physicalTime: 2500, logicalCounter: 0, nodeID: nodeB))

        let mergedAB = setA.merged(with: setB)
        let mergedBA = setB.merged(with: setA)

        XCTAssertEqual(mergedAB.elements, mergedBA.elements, "Merge must be commutative")
    }

    func testORSet_MergeIdempotent() {
        let node = UUID()
        var set = ORSet<String>()
        set.add("a", tag: HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: node))
        set.add("b", tag: HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: node))

        let merged = set.merged(with: set)
        XCTAssertEqual(merged.elements, set.elements, "Merge with self must be idempotent")
    }

    func testORSet_MergeAssociative() {
        let nodeA = UUID()
        let nodeB = UUID()
        let nodeC = UUID()

        var a = ORSet<String>()
        a.add("x", tag: HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: nodeA))

        var b = ORSet<String>()
        b.add("y", tag: HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: nodeB))

        var c = ORSet<String>()
        c.add("z", tag: HLCTimestamp(physicalTime: 3000, logicalCounter: 0, nodeID: nodeC))

        let leftFirst = a.merged(with: b).merged(with: c)
        let rightFirst = a.merged(with: b.merged(with: c))

        XCTAssertEqual(leftFirst.elements, rightFirst.elements, "Merge must be associative")
    }

    func testORSet_EmptyMerge() {
        var set = ORSet<String>()
        let empty = ORSet<String>()
        set.add("x", tag: HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: UUID()))

        let merged = set.merged(with: empty)
        XCTAssertEqual(merged.elements, set.elements, "Merge with empty set must be identity")
    }

    func testORSet_DuplicateAddsDifferentTags() {
        let nodeA = UUID()
        let nodeB = UUID()
        var set = ORSet<String>()

        set.add("item", tag: HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: nodeA))
        set.add("item", tag: HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: nodeB))

        // Remove only tombstones observed tags
        set.remove("item")
        XCTAssertFalse(set.contains("item"), "Remove should tombstone all observed tags")
    }
}
