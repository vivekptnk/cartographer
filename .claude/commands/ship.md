# /ship — Full release checklist

Run the complete pre-release verification:

## Checklist

### 1. Build
```bash
swift build 2>&1 | grep -i "warning\|error"
```
Must be zero warnings and zero errors.

### 2. Harnesses
```bash
swift test --filter HarnessTests
```
All harness tests must pass. Zero tolerance.

### 3. Full Test Suite
```bash
swift test
```
All tests must pass including unit tests and harnesses.

### 4. Benchmarks
```bash
swift test --filter BenchmarkTests -v
```
All benchmarks must meet their targets.

### 5. Code Quality
```bash
# No force unwraps in source
grep -rn '!\.' Sources/ --include="*.swift" | grep -v '//' | grep -v 'test'

# No TODOs in source
grep -rn 'TODO\|FIXME\|HACK' Sources/ --include="*.swift"

# No fatalError in source (except intentional)
grep -rn 'fatalError' Sources/ --include="*.swift"
```

### 6. Documentation
- [ ] Every public type has a doc comment
- [ ] README.md is current
- [ ] CLAUDE.md performance table has measured values
- [ ] All ADRs reflect current decisions

### 7. Git
```bash
git status
git log --oneline -10
```
- Clean working tree
- Meaningful commit messages
- Tag: `git tag v<version>`

## Report
Output a summary table showing pass/fail for each check.
