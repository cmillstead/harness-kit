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
staged_list=""
match_tmp=""
trap 'rm -f "$staged_list" "$match_tmp"' EXIT
staged_list="$(mktemp "${TMPDIR:-/tmp}/no-mocks-staged.XXXXXX")"
match_tmp="$(mktemp "${TMPDIR:-/tmp}/no-mocks-match.XXXXXX")"

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
        #
        # matches=$(pipeline) would only expose the LAST command's exit
        # status via $? — an error in an upstream grep stage (e.g. the
        # '^+++' or 'mock-ok:' filters) would be masked by a downstream
        # grep's rc, and could silently look like a clean "no match".
        # Redirect the pipeline's output to a file instead of a command
        # substitution so PIPESTATUS reflects every stage of the bare
        # pipeline, then check every grep's rc individually.
        set +e
        printf '%s\n' "$diff_out" \
            | grep -E '^\+' \
            | grep -v '^+++' \
            | grep -v 'mock-ok:' \
            | grep -E "$pattern" > "$match_tmp"
        pipe_rcs=("${PIPESTATUS[@]}")
        set -e

        # pipe_rcs[0] is printf; pipe_rcs[1..4] are the four greps in order.
        stage=0
        for rc in "${pipe_rcs[@]}"; do
            if [ "$stage" -gt 0 ] && [ "$rc" -gt 1 ]; then
                echo "no-mocks: grep stage $stage failed (rc=$rc) scanning $file for $pattern" >&2
                exit 1
            fi
            stage=$((stage + 1))
        done

        matches="$(cat "$match_tmp")"

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
