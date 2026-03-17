# /story $STORY_ID — Implement a story from the PRD

You are implementing story **$ARGUMENTS** from `docs/PRD.md`.

## Workflow

### Phase 1: Understand
1. Read `docs/PRD.md` and find the story matching the ID (e.g., CG-005)
2. Read `docs/ARCHITECTURE.md` to understand where this component fits
3. Read ALL relevant ADRs in `docs/adr/` — these are non-negotiable design decisions
4. Read the corresponding harness file in `Tests/CartographerTests/Harness/`
5. Summarize: what you're building, why, and what the harness expects

### Phase 2: Compile the Harness
1. Create any new types, protocols, or stubs needed for the harness to compile
2. Use `fatalError("Not yet implemented")` for method bodies
3. Run `swift build --build-tests` — fix until it compiles with zero errors

### Phase 3: Make the Harness Pass
1. Implement the real logic, one method at a time
2. After each method, run `swift test --filter <HarnessName>` 
3. Fix failures before moving to the next method
4. NEVER modify the harness to make it pass

### Phase 4: Benchmark
1. Run `swift test --filter Benchmark` for relevant benchmarks
2. Record results in the "Measured" column of the table in CLAUDE.md
3. If a benchmark fails its target, optimize before moving on

### Phase 5: Polish
1. Run the full test suite: `swift test`
2. Check for force unwraps: `grep -rn '!\.' Sources/ --include="*.swift" | grep -v '//'`
3. Check for warnings: `swift build 2>&1 | grep -i warning`
4. Commit with message: `feat(CG-XXX): <description>`

## Rules
- Read the ADRs. If you're about to make a decision that contradicts an ADR, stop and explain why.
- Never modify harness files.
- Every new public type must conform to `Sendable`.
- Every new public method must have a doc comment.
- Follow the naming conventions in CLAUDE.md.
