# /onboard — New contributor onboarding

Welcome to Cartographer! Here's everything you need to know.

## Step 1: Understand the Project
Read these files in order:
1. `CLAUDE.md` — What this is, how to build, code standards
2. `docs/ARCHITECTURE.md` — How the pieces fit together
3. `docs/PRD.md` — What's being built and what's left to do

## Step 2: Understand the Decisions
Read all ADRs in `docs/adr/`:
- ADR-001: Why raw SQLite over Core Data
- ADR-002: Why custom R-tree over SQLite extension
- ADR-003: Why CRDTs over Operational Transform
- ADR-004: Why CloudKit over custom backend
- ADR-005: Why harness-driven development

**These are non-negotiable.** Don't refactor toward different approaches without updating the ADR first.

## Step 3: Understand the Harnesses
The test harnesses define the behavioral contract:
- `Tests/CartographerTests/Harness/CRDTHarnessTests.swift` — HLC, LWW, OR-Set
- `Tests/CartographerTests/Harness/TileHarnessTests.swift` — Tile coordinate math, caching
- `Tests/CartographerTests/Harness/RTreeHarnessTests.swift` — Spatial index
- `Tests/CartographerTests/Harness/SyncHarnessTests.swift` — CRDT convergence

**Never modify harness files.** They are the spec.

## Step 4: Find Work
Check `docs/PRD.md` for unimplemented stories. Look for `fatalError("Not yet implemented")` in source files.

## Step 5: Implement
Use `/story CG-XXX` to implement a story with the full harness-driven workflow.

## Available Commands
- `/story CG-XXX` — Implement a story
- `/explain TOPIC` — Deep dive into a concept
- `/test TARGET` — Run and diagnose tests
- `/bench` — Run benchmarks
- `/ship` — Pre-release checklist
