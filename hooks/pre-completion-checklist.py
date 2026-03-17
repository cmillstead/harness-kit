#!/usr/bin/env python3
"""Claude Code PreToolUse hook: enforce verification before commits.

Fires before Bash tool calls that look like git commit or git push.
Checks that the agent has run verification commands (test, lint, typecheck)
in the current session before allowing the commit.

State is tracked via /tmp/claude-verification-{session_hash}.json
"""

import hashlib
import json
import os
import re
import sys
import time

STATE_DIR = "/tmp"
STALE_SECONDS = 7200  # 2 hours

# Commands that count as verification
VERIFICATION_PATTERNS = [
    r'\bnpm\s+test\b',
    r'\bnpm\s+run\s+test\b',
    r'\bnpx\s+jest\b',
    r'\bnpx\s+vitest\b',
    r'\bnpx\s+pytest\b',
    r'\bpytest\b',
    r'\bcargo\s+test\b',
    r'\bgo\s+test\b',
    r'\bnpm\s+run\s+lint\b',
    r'\bnpx\s+eslint\b',
    r'\bnpx\s+tsc\s+--noEmit\b',
    r'\btsc\s+--noEmit\b',
    r'\bmypy\b',
    r'\bruff\s+check\b',
    r'\bcargo\s+clippy\b',
    r'\bmake\s+test\b',
    r'\bmake\s+lint\b',
    r'\bmake\s+check\b',
    r'\bbash\s+-n\b',
    r'\bshellcheck\b',
]

# Commands that trigger the checklist
COMMIT_PATTERNS = [
    r'\bgit\s+commit\b',
    r'\bgit\s+push\b',
]


def get_state_file() -> str:
    session_id = os.environ.get("CLAUDE_SESSION_ID", os.environ.get("SESSION_ID", "default"))
    h = hashlib.sha256(session_id.encode()).hexdigest()[:12]
    return os.path.join(STATE_DIR, f"claude-verification-{h}.json")


def load_state(path: str) -> dict:
    try:
        with open(path) as f:
            state = json.load(f)
        if time.time() - state.get("last_updated", 0) > STALE_SECONDS:
            return {"verifications": [], "last_updated": time.time()}
        return state
    except (FileNotFoundError, json.JSONDecodeError):
        return {"verifications": [], "last_updated": time.time()}


def save_state(path: str, state: dict):
    state["last_updated"] = time.time()
    with open(path, "w") as f:
        json.dump(state, f)


def is_verification(command: str) -> bool:
    return any(re.search(p, command) for p in VERIFICATION_PATTERNS)


def is_commit(command: str) -> bool:
    return any(re.search(p, command) for p in COMMIT_PATTERNS)


def main():
    event = json.load(sys.stdin)
    tool_name = event.get("tool_name", "")

    if tool_name != "Bash":
        return

    command = event.get("tool_input", {}).get("command", "")
    if not command:
        return

    state_file = get_state_file()
    state = load_state(state_file)

    # Track verification commands
    if is_verification(command):
        state["verifications"].append({
            "command": command[:100],
            "time": time.time(),
        })
        # Keep last 20
        state["verifications"] = state["verifications"][-20:]
        save_state(state_file, state)
        return

    # Check before commit/push
    if is_commit(command):
        # Skip for docs-only repos (no build/test infrastructure)
        project_markers = [
            # JavaScript / TypeScript
            "package.json", "tsconfig.json", "deno.json",
            # Python
            "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt",
            "Pipfile", "tox.ini",
            # Rust
            "Cargo.toml",
            # Go
            "go.mod",
            # Java / Kotlin / Scala
            "pom.xml", "build.gradle", "build.gradle.kts", "build.sbt",
            # C# / .NET
            "Directory.Build.props",
            # Ruby
            "Gemfile", "Rakefile",
            # PHP
            "composer.json",
            # Swift
            "Package.swift",
            # Dart / Flutter
            "pubspec.yaml",
            # Elixir
            "mix.exs",
            # Haskell
            "stack.yaml", "cabal.project",
            # C / C++
            "CMakeLists.txt", "meson.build", "configure.ac",
            # Zig
            "build.zig",
            # Clojure
            "deps.edn", "project.clj",
            # Julia
            "Project.toml",
            # Generic
            "Makefile", "Justfile",
        ]
        cwd = os.getcwd()
        has_project = any(os.path.exists(os.path.join(cwd, m)) for m in project_markers)
        # Check for glob-pattern markers (.csproj, .sln, .xcodeproj)
        if not has_project:
            import glob
            glob_markers = ["*.csproj", "*.sln", "*.xcodeproj", "*.nimble"]
            has_project = any(glob.glob(os.path.join(cwd, g)) for g in glob_markers)
        if not has_project:
            return  # docs-only repo, no verification needed

        # Look for recent verifications (within last 30 minutes)
        recent = [v for v in state["verifications"]
                  if time.time() - v["time"] < 1800]

        has_tests = any(
            re.search(r'test|jest|vitest|pytest|cargo\s+test|go\s+test|bash\s+-n', v["command"])
            for v in recent
        )
        has_lint = any(
            re.search(r'lint|eslint|tsc|mypy|ruff|clippy|bash\s+-n|shellcheck', v["command"])
            for v in recent
        )

        missing = []
        if not has_tests:
            missing.append("tests (npm test, pytest, cargo test, etc.)")
        if not has_lint:
            missing.append("linting/typecheck (npm run lint, tsc --noEmit, mypy, etc.)")

        if missing:
            msg = "PRE-COMPLETION CHECKLIST FAILED\n\n"
            msg += "You are about to commit/push but have NOT run:\n"
            for m in missing:
                msg += f"  - {m}\n"
            msg += "\nYou MUST run verification before committing. "
            msg += "Golden Principle #8: Verify Before Claiming Done.\n\n"
            msg += "Run the missing checks first, then retry the commit.\n"
            msg += "If tests/linting don't apply to this repo, explain why to the user."

            print(json.dumps({
                "decision": "block",
                "reason": msg,
            }))
            return


if __name__ == "__main__":
    main()
