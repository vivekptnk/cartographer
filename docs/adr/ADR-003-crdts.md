# ADR-003: CRDTs Over Operational Transform

## Status
Accepted

## Context
Multiple devices edit annotations offline and must converge to the same state when syncing.

## Decision
Use operation-based CRDTs (HLC + LWW-Register + OR-Set) for conflict resolution.

## Rationale
- **No central server required.** OT requires a central server to order operations. CRDTs converge regardless of operation order — perfect for offline-first.
- **Mathematical guarantees.** CRDTs are provably convergent if merge is commutative, associative, and idempotent. We can unit-test these properties directly.
- **Field-level resolution.** LWW-Register per annotation field means editing the title on device A and the body on device B both survive — no whole-object conflict.
- **CloudKit compatibility.** CloudKit has no built-in conflict resolution. CRDTs make conflict resolution a non-issue at the transport layer.

## CRDT Type Mapping
| Data | CRDT | Semantics |
|------|------|-----------|
| Annotation fields (title, body, coordinate) | LWW-Register | Last writer wins per field |
| Annotation set within a project | OR-Set | Add wins over concurrent remove |
| Operation ordering | HLC | Causal ordering without central clock |

## Consequences
- Must implement HLC, LWW, and OR-Set from scratch
- OR-Set tombstones grow unbounded — need periodic garbage collection
- HLC requires node ID uniqueness (UUID per device)
- More complex than simple last-write-wins at the object level, but more correct

## Alternatives Rejected
- **Operational Transform:** Requires central server, complex transformation functions.
- **Last-write-wins (whole object):** Loses concurrent edits to different fields.
- **Manual conflict UI:** Bad UX for field users — they need automatic resolution.
