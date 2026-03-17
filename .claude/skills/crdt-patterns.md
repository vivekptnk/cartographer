# CRDT Patterns for Cartographer

## Core Principle
Every mutation is an operation. Operations are the unit of sync. CRDTs guarantee that applying the same set of operations in any order produces the same final state.

## Hybrid Logical Clock (HLC)

```swift
// HLC = (physical_time_ms, logical_counter, node_id)
// tick(): max(now, last.physical) → if same, increment logical; else reset to 0
// merge(remote): max(now, last.physical, remote.physical) → adjust logical accordingly

let ts = await clock.tick()        // Always > previous tick
let merged = await clock.merge(remote: remoteTS)  // Always > both local and remote
```

**Key invariant:** Monotonically increasing. No two timestamps from the same clock are equal.

## Last-Writer-Wins Register

```swift
// Per-field conflict resolution. Each field is an independent LWW register.
struct LWWRegister<Value> {
    var value: Value
    var timestamp: HLCTimestamp

    mutating func merge(_ remote: Self) {
        if remote.timestamp > timestamp {
            value = remote.value
            timestamp = remote.timestamp
        }
    }
}

// Usage: annotation fields
var title = LWWRegister(value: "Park A", timestamp: t1)
title.set("Park Alpha", at: t2)  // t2 > t1 → updates
title.set("Old Name", at: t0)    // t0 < t2 → rejected
```

**Properties to test:** commutative, associative, idempotent.

## Observed-Remove Set (OR-Set)

```swift
// Add-wins: concurrent add + remove → element exists
// Each add tagged with unique HLC. Remove tombstones only observed tags.

var set = ORSet<UUID>()          // Project's annotation set
set.add(annotationID, tag: ts)   // Unique tag per add
set.remove(annotationID)         // Tombstones all current tags
// If another device concurrently adds with a different tag → add wins
```

**Merge:** Union of all entries + union of all tombstones. Element exists if it has any non-tombstoned tag.

## Operation Log Pattern

```swift
// Every mutation → Operation → append to log
let op = Operation(
    type: .update,
    entityType: .annotation,
    entityID: annotationID,
    projectID: projectID,
    hlc: await clock.tick(),
    payload: try JSONEncoder().encode(["title": "New Title"])
)
await operationLog.append(op)

// Materialize: replay all operations for an entity → current state
let annotation = await operationLog.materialize(entityID: annotationID)
```

## Convergence Test Pattern

```swift
// Generate N operations on N replicas
// Merge all replicas in every permutation
// Assert: all replicas have identical state after merge
for permutation in allPermutations {
    var result = emptyState
    for replicaIndex in permutation {
        result.merge(replicas[replicaIndex])
    }
    XCTAssertEqual(result, expectedConvergedState)
}
```
