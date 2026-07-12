#!/usr/bin/env bash
# Git pre-commit hook: block mock usage in test files.
# Works with any AI agent or human — enforced at git level.
#
# Checks staged files for mock patterns. If found, blocks the commit
# with remediation instructions.
#
# Allowlist: add '# mock-ok: <reason>' on the same line to exempt.

set -euo pipefail

MOCK_PATTERNS=(
    # Python
    'from unittest\.mock import'
    'from unittest import mock'
    'import unittest\.mock'
    'mock\.patch'
    '@patch'
    'MagicMock'
    'AsyncMock'
    'PropertyMock'
    'monkeypatch'
    'create_autospec'
    # TypeScript/JavaScript
    'jest\.mock'
    'jest\.spyOn'
    'vi\.mock'
    'vi\.spyOn'
    'sinon\.'
    # Rust
    '#\[mockall::automock\]'
    'mock!\s*\{'
)

TEST_PATTERNS='test[s]?[/_]|_test\.|\.test\.|\.spec\.|test_'

violations=()

# Enumerate staged files into a checked temp file. A process substitution
# here would silently swallow a git failure under set -euo pipefail and the
# loop would just see empty input, scanning nothing while exiting 0.
staged_list="$(mktemp "${TMPDIR:-/tmp}/no-mocks-staged.XXXXXX")"
trap 'rm -f "$staged_list"' EXIT

if ! git diff --cached --name-only --diff-filter=ACMR -z > "$staged_list"; then
    echo "no-mocks: failed to enumerate staged files" >&2
    exit 1
fi

# Check only staged files
while IFS= read -r -d '' file; do
    # Skip non-test files
    if ! echo "$file" | grep -qE "$TEST_PATTERNS"; then
        continue
    fi

    diff_out="$(git diff --cached --unified=0 -- "$file")" || {
        echo "no-mocks: git diff failed for $file" >&2
        exit 1
    }

    for pattern in "${MOCK_PATTERNS[@]}"; do
        # Find matches, exclude lines with mock-ok. Distinguish "no match"
        # (grep rc 1, tolerated — this includes an earlier grep in the chain
        # filtering everything out) from a genuine grep error (rc > 1) so an
        # error can't be mistaken for a clean pass.
        set +e
        matches=$(printf '%s\n' "$diff_out" \
            | grep -E '^\+' \
            | grep -v '^+++' \
            | grep -v 'mock-ok:' \
            | grep -E "$pattern")
        grep_rc=$?
        set -e

        if [ "$grep_rc" -gt 1 ]; then
            echo "no-mocks: grep failed (rc=$grep_rc) scanning $file for $pattern" >&2
            exit 1
        fi

        if [ -n "$matches" ]; then
            violations+=("$file: $pattern")
        fi
    done
done < "$staged_list"

if [ ${#violations[@]} -gt 0 ]; then
    echo "============================================"
    echo "BLOCKED: Mock usage detected in test files"
    echo "============================================"
    echo ""
    echo "Golden Principle #1: Real Over Mocks."
    echo "This codebase requires REAL implementations, not mocks."
    echo ""
    echo "Violations:"
    for v in "${violations[@]}"; do
        echo "  - $v"
    done
    echo ""
    echo "REMEDIATION — replace mocks with real implementations:"
    echo "  Database:     SQLite temp DB or Docker test container"
    echo "  HTTP client:  httpx.AsyncClient(app=app) or real test server"
    echo "  File system:  tempfile.mkdtemp() or tmp_path fixture"
    echo "  Redis:        Docker test container or fakeredis"
    echo "  External API: ONLY mock if no sandbox exists"
    echo "                Add '# mock-ok: <reason>' to exempt"
    echo ""
    exit 1
fi
