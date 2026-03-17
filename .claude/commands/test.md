# /test $TARGET — Run and diagnose tests

Run the test target: **$ARGUMENTS**

## Workflow

1. Run the specified tests:
   - If target is a harness: `swift test --filter <Harness>HarnessTests`
   - If target is "all": `swift test`
   - If target is "bench": `swift test --filter BenchmarkTests`
   - If target is a specific test: `swift test --filter <target>`

2. If all pass: Report results with ✅, show count of passing tests.

3. If any fail:
   a. Read the failing test's assertion message
   b. Read the harness file to understand the expected behavior
   c. Read the implementation file
   d. Diagnose the root cause
   e. Propose a fix
   f. Apply the fix
   g. Re-run the failing test
   h. If it passes, run the full harness to check for regressions

## CRITICAL RULES
- **NEVER modify harness files** (`Tests/CartographerTests/Harness/*.swift`)
- If a harness test seems wrong, explain why and ask for confirmation before any change
- Always run the full harness after fixing a single test — fixes can cause regressions
