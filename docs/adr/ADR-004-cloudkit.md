# ADR-004: CloudKit Over Custom Backend

## Status
Accepted

## Context
We need to sync CRDT operations between devices.

## Decision
Use CloudKit private database with custom zones.

## Rationale
- **Zero infrastructure.** No server to deploy, manage, or pay for.
- **Free tier is generous.** 5GB per user for private database — enough for millions of operations.
- **Built-in auth.** iCloud account = authenticated. No login flow to build.
- **Change tokens.** `CKServerChangeToken` enables efficient delta sync — pull only what's new.
- **Background fetch.** `CKSubscription` + background app refresh keeps devices current.

## Consequences
- Locked to Apple ecosystem (no Android/web sync)
- CloudKit rate limits may throttle bulk sync
- Must handle `CKError` cases: `.serverRecordChanged`, `.zoneNotFound`, `.quotaExceeded`
- Testing requires iCloud account and network (mock transport for unit tests)

## Alternatives Rejected
- **Firebase Firestore:** Cross-platform but adds Google dependency, costs money at scale.
- **Custom WebSocket server:** Full control but requires infrastructure.
- **iCloud Key-Value Store:** 1MB limit, no structured queries.
