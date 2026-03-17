// MARK: - Sync Harness Tests
// Validates that CRDT operations converge regardless of application order.
// Simulates multi-device scenarios without requiring actual CloudKit.
// RULE: Never modify this file to make tests pass. Fix the implementation instead.

import XCTest
@testable import Cartographer

final class SyncHarnessTests: XCTestCase {

    // MARK: - Convergence Tests

    /// Two devices apply the same operations in different orders → identical state.
    func testConvergence_SameOps_DifferentOrder() async {
        let nodeA = UUID()
        let nodeB = UUID()
        let clockA = HLCClock(nodeID: nodeA)
        let clockB = HLCClock(nodeID: nodeB)

        let projectID = UUID()
        let annotationID = UUID()

        // Device A: create annotation, then update title
        let t1 = await clockA.tick()
        let t2 = await clockA.tick()

        // Device B: independently update body
        let t3 = await clockB.tick()

        // Build LWW registers simulating the two devices
        var stateA_title = LWWRegister(value: "Original", timestamp: t1)
        stateA_title.set("Updated Title", at: t2)
        var stateA_body = LWWRegister(value: "Original Body", timestamp: t1)

        var stateB_title = LWWRegister(value: "Original", timestamp: t1)
        var stateB_body = LWWRegister(value: "Original Body", timestamp: t1)
        stateB_body.set("Updated Body", at: t3)

        // Merge A ← B
        stateA_title.merge(stateB_title)
        stateA_body.merge(stateB_body)

        // Merge B ← A
        stateB_title.merge(LWWRegister(value: "Updated Title", timestamp: t2))
        stateB_body.merge(stateA_body)

        // Both devices must converge
        XCTAssertEqual(stateA_title.value, stateB_title.value, "Titles must converge")
        XCTAssertEqual(stateA_body.value, stateB_body.value, "Bodies must converge")
    }

    /// Three devices with concurrent edits → all converge.
    func testConvergence_ThreeDevices() async {
        let nodes = (0..<3).map { _ in UUID() }
        let clocks = nodes.map { HLCClock(nodeID: $0) }

        // Each device sets a different value for the same field
        let t0 = await clocks[0].tick()
        let t1 = await clocks[1].tick()
        let t2 = await clocks[2].tick()

        let reg0 = LWWRegister(value: "Device0", timestamp: t0)
        let reg1 = LWWRegister(value: "Device1", timestamp: t1)
        let reg2 = LWWRegister(value: "Device2", timestamp: t2)

        // All permutations of merge order must produce the same result
        let merged_012 = reg0.merged(with: reg1).merged(with: reg2)
        let merged_021 = reg0.merged(with: reg2).merged(with: reg1)
        let merged_102 = reg1.merged(with: reg0).merged(with: reg2)
        let merged_120 = reg1.merged(with: reg2).merged(with: reg0)
        let merged_201 = reg2.merged(with: reg0).merged(with: reg1)
        let merged_210 = reg2.merged(with: reg1).merged(with: reg0)

        let expected = merged_012.value
        XCTAssertEqual(merged_021.value, expected, "All merge orderings must converge")
        XCTAssertEqual(merged_102.value, expected, "All merge orderings must converge")
        XCTAssertEqual(merged_120.value, expected, "All merge orderings must converge")
        XCTAssertEqual(merged_201.value, expected, "All merge orderings must converge")
        XCTAssertEqual(merged_210.value, expected, "All merge orderings must converge")
    }

    /// OR-Set: two devices add and remove concurrently → converge with add-wins.
    func testConvergence_ORSet_ConcurrentAddRemove() {
        let nodeA = UUID()
        let nodeB = UUID()

        // Device A: add X, add Y
        var setA = ORSet<String>()
        setA.add("X", tag: HLCTimestamp(physicalTime: 1000, logicalCounter: 0, nodeID: nodeA))
        setA.add("Y", tag: HLCTimestamp(physicalTime: 2000, logicalCounter: 0, nodeID: nodeA))

        // Device B: add X, remove X, add Z
        var setB = ORSet<String>()
        setB.add("X", tag: HLCTimestamp(physicalTime: 1500, logicalCounter: 0, nodeID: nodeB))
        setB.remove("X")
        setB.add("Z", tag: HLCTimestamp(physicalTime: 3000, logicalCounter: 0, nodeID: nodeB))

        // Merge both ways
        let mergedAB = setA.merged(with: setB)
        let mergedBA = setB.merged(with: setA)

        XCTAssertEqual(mergedAB.elements, mergedBA.elements, "OR-Set merge must be commutative")
        // A's add of X (tag nodeA/1000) was never seen by B's remove → X survives
        XCTAssertTrue(mergedAB.contains("X"), "Concurrent add must win over concurrent remove")
        XCTAssertTrue(mergedAB.contains("Y"), "Y was never removed")
        XCTAssertTrue(mergedAB.contains("Z"), "Z was never removed")
    }

    /// Simulate network partition: both devices edit offline, then sync.
    func testConvergence_NetworkPartition_ThenSync() async {
        let nodeA = UUID()
        let nodeB = UUID()
        let clockA = HLCClock(nodeID: nodeA)
        let clockB = HLCClock(nodeID: nodeB)

        // --- OFFLINE PHASE ---

        // Device A: edit title 3 times
        var titleA = LWWRegister(value: "v0", timestamp: await clockA.tick())
        titleA.set("v1_A", at: await clockA.tick())
        titleA.set("v2_A", at: await clockA.tick())

        // Device B: edit title 2 times (unaware of A's edits)
        var titleB = LWWRegister(value: "v0", timestamp: await clockB.tick())
        titleB.set("v1_B", at: await clockB.tick())

        // --- SYNC PHASE ---

        // A merges B's state
        var resolvedA = titleA
        resolvedA.merge(titleB)

        // B merges A's state
        var resolvedB = titleB
        resolvedB.merge(titleA)

        XCTAssertEqual(resolvedA.value, resolvedB.value, "Must converge after partition heals")
    }

    // MARK: - Fuzz Tests

    /// Randomly generate operations and verify convergence across N replicas.
    func testFuzz_RandomOperations_Converge() async {
        let replicaCount = 5
        let opsPerReplica = 20

        let nodes = (0..<replicaCount).map { _ in UUID() }
        var sets = nodes.map { _ in ORSet<Int>() }

        // Each replica generates random add/remove operations
        for (i, node) in nodes.enumerated() {
            for j in 0..<opsPerReplica {
                let element = Int.random(in: 0..<10) // Small element space to force collisions
                let tag = HLCTimestamp(
                    physicalTime: UInt64(i * 1000 + j),
                    logicalCounter: UInt16(j),
                    nodeID: node
                )
                if Bool.random() {
                    sets[i].add(element, tag: tag)
                } else {
                    sets[i].remove(element)
                }
            }
        }

        // Merge all replicas into each replica
        var converged = [ORSet<Int>]()
        for i in 0..<replicaCount {
            var merged = sets[i]
            for j in 0..<replicaCount where j != i {
                merged.merge(sets[j])
            }
            converged.append(merged)
        }

        // All replicas must have the same elements
        let expected = converged[0].elements
        for i in 1..<replicaCount {
            XCTAssertEqual(converged[i].elements, expected, "Replica \(i) must converge with replica 0")
        }
    }
}
