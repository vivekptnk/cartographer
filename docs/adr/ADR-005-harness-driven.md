# ADR-005: Harness-Driven Development Over TDD

## Status
Accepted

## Context
This repo is designed for AI-assisted development with Claude Code. Traditional TDD (write one test, make it pass, refactor) is optimized for human developers working incrementally. AI agents work better with a complete contract to implement against.

## Decision
Use harness-driven development: write complete test harnesses defining the full behavioral contract of each component before writing any implementation.

## Rationale
- **AI agents need complete context.** A harness file gives Claude Code the full picture: all types needed, all behaviors expected, all edge cases covered. The agent can plan the entire implementation before writing code.
- **Harnesses are the spec.** The PRD describes what to build in prose. The harness describes it in executable Swift. There's no ambiguity.
- **Prevents regression.** When an agent implements CG-008 (LWW-Register), it can't accidentally break CG-007 (HLC) because the HLC harness catches it.
- **Benchmark integration.** Harnesses include performance assertions, so agents know the perf targets from the start.
- **Contributor onboarding.** A new contributor (human or AI) reads the harness and knows exactly what the implementation must do.

## Harness Structure
```
Tests/CartographerTests/
├── Harness/                    # THE source of truth
│   ├── CRDTHarnessTests.swift  # HLC, LWW, ORSet contracts
│   ├── TileHarnessTests.swift  # Cache, overlay, download contracts
│   ├── RTreeHarnessTests.swift # Spatial index contracts
│   └── SyncHarnessTests.swift  # Convergence contracts
├── CRDT/                       # Additional unit tests (written during implementation)
├── TileEngine/                 # Additional unit tests
├── Spatial/                    # Additional unit tests
└── Benchmarks/                 # Performance regression tests
```

## Rules
1. **Never modify a harness to make it pass.** If a harness test fails, the implementation is wrong.
2. **Harnesses test behavior, not implementation.** They use only public API.
3. **Harnesses include edge cases.** Concurrent operations, empty inputs, boundary values.
4. **Benchmarks are in a separate target** but harnesses include basic perf smoke tests.

## Consequences
- More upfront work before any implementation code
- Harnesses may need updates when the public API design evolves (but this should be rare and deliberate)
- Agents may try to modify harnesses — CLAUDE.md explicitly forbids this
