#!/usr/bin/env python3
"""
Model routing hook for Claude Code multi-model strategy.
Haiku: linting, formatting, simple queries
Sonnet: implementation, test writing, debugging
Opus: architecture decisions, CRDT design, complex refactors

Usage: This hook is informational — Claude Code uses it to decide
which model to route subtasks to when using task delegation.
"""

import sys
import json

# Task → model mapping
ROUTING = {
    # Haiku tasks (fast, cheap)
    "lint": "haiku",
    "format": "haiku",
    "grep": "haiku",
    "find": "haiku",
    "simple_question": "haiku",

    # Sonnet tasks (balanced)
    "implement": "sonnet",
    "write_test": "sonnet",
    "debug": "sonnet",
    "refactor_small": "sonnet",
    "documentation": "sonnet",

    # Opus tasks (complex reasoning)
    "architecture": "opus",
    "crdt_design": "opus",
    "algorithm_design": "opus",
    "code_review": "opus",
    "refactor_large": "opus",
    "performance_analysis": "opus",
}

if __name__ == "__main__":
    task_type = sys.argv[1] if len(sys.argv) > 1 else "implement"
    model = ROUTING.get(task_type, "sonnet")
    print(json.dumps({"task": task_type, "model": model}))
