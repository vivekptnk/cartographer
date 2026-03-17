# /bench — Run all benchmarks and report

## Workflow

1. Run benchmarks: `swift test --filter BenchmarkTests -v 2>&1 | tee /tmp/bench-output.txt`

2. Parse the output for all lines matching `⏱`

3. Format results as a table:

| Benchmark | Result | Target | Status |
|-----------|--------|--------|--------|
| HLC tick | Xμs | < 1μs | ✅/❌ |
| LWW merge 1K | Xms | < 50ms | ✅/❌ |
| OR-Set merge 1K | Xms | < 50ms | ✅/❌ |
| R-tree insert (avg) | Xμs | < 1ms | ✅/❌ |
| R-tree range query 10K | Xms | < 10ms | ✅/❌ |
| R-tree bulk load 10K | Xms | — | — |
| Tile coord conversion | Xμs | < 10μs | ✅/❌ |

4. Update the "Measured" column in `CLAUDE.md` performance targets table

5. If any benchmark fails its target:
   - Profile the hot path
   - Suggest optimization (algorithm change, allocation reduction, etc.)
   - Do NOT trade correctness for speed — harness must still pass after optimization
