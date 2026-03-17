#!/bin/bash
# Pre-commit checks for Cartographer

set -e

# Block direct commits to main
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [ "$BRANCH" = "main" ]; then
    echo "❌ Direct commits to main are blocked. Use a feature branch."
    exit 1
fi

# Check for force unwraps in Sources/
FORCE_UNWRAPS=$(grep -rn '!\.' Sources/ --include="*.swift" | grep -v '//' | grep -v 'test' || true)
if echo "$FORCE_UNWRAPS" | grep -qE '\w!\.'; then
    echo "❌ Force unwraps found in Sources/:"
    echo "$FORCE_UNWRAPS"
    exit 1
fi

# Check for modified harness files
HARNESS_CHANGES=$(git diff --cached --name-only | grep "Tests/CartographerTests/Harness/" || true)
if [ -n "$HARNESS_CHANGES" ]; then
    echo "❌ Harness files must not be modified:"
    echo "$HARNESS_CHANGES"
    echo "Harnesses are the source of truth. Fix the implementation, not the harness."
    exit 1
fi

# Check for fatalError (excluding stubs that are expected)
FATAL_ERRORS=$(grep -rn 'fatalError' Sources/ --include="*.swift" | grep -v 'Not yet implemented' || true)
if [ -n "$FATAL_ERRORS" ]; then
    echo "⚠️  Unexpected fatalError found (not a stub):"
    echo "$FATAL_ERRORS"
fi

echo "✅ Pre-commit checks passed"
