# /explain $TOPIC — Deep dive before coding

You are teaching a concept before any code is written. The topic is: **$ARGUMENTS**

## Teaching Format

### 1. What Is It?
Explain the concept in plain language. Use a real-world analogy.

### 2. Why Does Cartographer Need It?
Connect this concept directly to the architecture in `docs/ARCHITECTURE.md`. Show where it lives in the system and what depends on it.

### 3. How Does It Work?
Step-by-step algorithm walkthrough. Use ASCII diagrams. Show the data structures involved. Walk through an example with concrete values.

### 4. The Tricky Parts
What are the edge cases? What are the common mistakes? What would happen if we got this wrong?

### 5. How Cartographer Implements It
Reference the relevant source files and harness tests. Show how the concept maps to our Swift types.

### 6. Quiz
Ask 3 questions to verify understanding:
- One definitional
- One "what happens when..."
- One "how would you modify this to..."

## Common Topics
- `CRDT` → Start with LWW-Register, build to OR-Set, explain convergence
- `HLC` → Lamport clocks → HLC extension → why not NTP alone
- `R-tree` → MBR concept → insert/split → range query → compare to quadtree
- `WAL mode` → SQLite journal modes → why WAL for concurrent reads
- `Slippy map tiles` → z/x/y scheme → Mercator projection → tile math
- `Event sourcing` → operation log → materialization → snapshots
