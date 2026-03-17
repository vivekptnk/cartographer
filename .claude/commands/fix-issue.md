# /fix-issue $ISSUE — Diagnose and fix a bug

Fixing issue: **$ARGUMENTS**

## Workflow

### 1. Reproduce
- Read the issue description
- Write a failing test that reproduces the bug (in the appropriate test directory, NOT in Harness/)
- Run the test to confirm it fails

### 2. Diagnose
- Read the failing test's assertion
- Trace the code path from the test into the implementation
- Identify the root cause
- Check: does any harness test already cover this? If so, the harness should be failing too.

### 3. Fix
- Apply the minimal fix
- Run the new test — must pass
- Run the relevant harness — must still pass
- Run `swift test` — everything must pass

### 4. Verify
- Run benchmarks if the fix touches a hot path: `swift test --filter Benchmark`
- Check for new warnings: `swift build 2>&1 | grep -i warning`

### 5. Commit
```
fix(CG-XXX): <description>

Fixes #<issue_number>

Root cause: <explanation>
Test: <new test name>
```
