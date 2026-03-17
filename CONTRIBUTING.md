# Contributing to Cartographer

## For AI-Assisted Contributors (Claude Code)

### Getting Started
```bash
git clone <repo>
cd Cartographer
claude
> /onboard
```

### Implementing a Story
```
/story CG-005
```

This will:
1. Read the PRD and architecture docs
2. Read the relevant ADRs
3. Read the harness that defines the behavioral contract
4. Create stubs → make the harness compile → make the harness pass → benchmark

### Available Commands
| Command | What it does |
|---------|-------------|
| `/story CG-XXX` | Implement a story end-to-end |
| `/explain TOPIC` | Deep dive into a concept before coding |
| `/test TARGET` | Run and diagnose tests |
| `/bench` | Run benchmarks, update CLAUDE.md |
| `/ship` | Full pre-release checklist |
| `/fix-issue DESC` | Diagnose and fix a bug |
| `/onboard` | New contributor walkthrough |

### Rules
1. **Never modify harness files.** Files in `Tests/CartographerTests/Harness/` are the spec. If a harness test fails, the implementation is wrong.
2. **Read the ADRs.** Before changing any architectural decision, read `docs/adr/`. If you disagree with a decision, update the ADR with a new "Status: Superseded" entry — don't silently refactor.
3. **No external dependencies.** Apple frameworks + system SQLite only.
4. **Strict concurrency.** All code must compile with Swift 6 strict concurrency. Every public type must be `Sendable`.
5. **No force unwraps in Sources/.** Tests can use `!` — source code cannot.

## For Human Contributors

### Branch Strategy
- `main` — protected, requires CI pass
- `develop` — integration branch
- Feature branches: `feat/CG-XXX-description`
- Bug fixes: `fix/CG-XXX-description`

### Commit Messages
```
feat(CG-005): implement R-tree with quadratic split
fix(CG-008): LWW merge now handles equal timestamps deterministically
docs: update architecture diagram with sync flow
bench: add R-tree nearest-neighbor benchmark
```

### PR Checklist
- [ ] All harness tests pass (`swift test --filter HarnessTests`)
- [ ] Full test suite passes (`swift test`)
- [ ] Benchmarks meet targets (`swift test --filter BenchmarkTests`)
- [ ] No force unwraps in Sources/
- [ ] No build warnings
- [ ] No harness files modified
- [ ] New public types have doc comments
- [ ] ADRs still accurate

### Testing Philosophy
- **Harness tests** = behavioral contract, never modified
- **Unit tests** (in module subdirectories) = additional coverage written during implementation
- **Benchmarks** = performance regression gates
- **Convergence tests** = CRDT correctness via multi-replica simulation

### Where to Start
Check `docs/PRD.md` for stories. Grep for `fatalError("Not yet implemented")` in Sources/ to find stubs waiting for implementation.
