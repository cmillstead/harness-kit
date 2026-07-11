#!/usr/bin/env bash
# hooks/stop-verify.sh
#
# Claude Code Stop hook — runs before the agent is allowed to finish.
#
# WARNING: enabling this hook EXECUTES repository-defined commands
# (npm test/lint, pytest, cargo). Only enable it in repositories you trust.
#
# Install: copy to .claude/hooks/stop-verify.sh; wire into .claude/settings.json
#          (see hooks/settings-snippet.json).
# See: The Harness Engineering Playbook, Chapter 12b.
#
# Loop safety — TWO independent guards (defense in depth). The CC hooks docs DO
# document that a Stop hook exiting 2 blocks the stop and continues the
# conversation, and provide stop_hook_active so a hook can tell it is re-running
# as a result of its own prior block (verified against the live docs, round 3).
# We keep a second guard so a payload that omits the field, or a docs/shape
# drift, still can't produce an unbounded loop:
#   1. stop_hook_active (parsed structurally from stdin): a retried stop that is
#      still red WARNS and allows (exit 0) instead of blocking.
#   2. A per-(session, project) block counter in a VALIDATED 0700 state dir: if
#      this repo has been blocked >= 2 times in the last 10 minutes, WARN and
#      allow regardless of stop_hook_active. A green run resets the counter.
# A first failing stop blocks by exiting 2 with the reason on stderr.

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# One python3 call (already a kit dep) parses stop_hook_active AND resolves a
# VALIDATED per-(session, project) counter path — reusing the checklist's
# state-dir discipline (R3-7): lstat must show a real, non-symlink, self-owned
# 0700 dir, else no counter is used (COUNTER stays empty and Guard 2 is skipped).
# The python block NEVER raises (R4-5): even if the state dir cannot be created it
# still prints the stop_hook_active flag, so Guard 1 is never lost.
INPUT="$(cat)"
parsed="$(printf '%s' "$INPUT" | python3 -c '
import hashlib, json, os, stat, sys, tempfile

try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    data = {}

active = "1" if data.get("stop_hook_active") is True else "0"
session = str(data.get("session_id") or "default")
root = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())


def secure_state_dir():
    # R4-5: NEVER raise — a crash here would print no lines, and bash would then
    # default STOP_ACTIVE=0 with no counter, losing BOTH loop guards. On any
    # security or I/O failure return "" so Guard 2 is skipped but Guard 1 stands.
    base = os.path.join(tempfile.gettempdir(), "claude-harness-%d" % os.getuid())
    try:
        os.makedirs(base, mode=0o700)   # no exist_ok — validate the result below
    except FileExistsError:
        pass                            # already present, or lost a create race
    except OSError:
        return ""
    # R5-3: confirm a real, self-owned, NON-symlink dir BEFORE any chmod, so a
    # symlink planted in the create window never has its TARGET mode changed.
    try:
        info = os.lstat(base)
    except OSError:
        return ""
    if not (
        stat.S_ISDIR(info.st_mode)
        and not stat.S_ISLNK(info.st_mode)
        and info.st_uid == os.getuid()
    ):
        return ""
    if stat.S_IMODE(info.st_mode) != 0o700:
        try:
            os.chmod(base, 0o700)       # tighten only the validated self-owned dir
            info = os.lstat(base)
        except OSError:
            return ""
    ok = (
        stat.S_ISDIR(info.st_mode)
        and not stat.S_ISLNK(info.st_mode)
        and info.st_uid == os.getuid()
        and stat.S_IMODE(info.st_mode) == 0o700
    )
    return base if ok else ""


# active is printed UNCONDITIONALLY (secure_state_dir never raises), so Guard 1
# (stop_hook_active) is preserved even when the state dir is unusable.
state = secure_state_dir()
counter = ""
if state:
    key = hashlib.sha256(("%s\0%s" % (session, root)).encode()).hexdigest()[:16]
    counter = os.path.join(state, "stop-%s" % key)

print(active)
print(counter)
')"
STOP_ACTIVE="$(printf '%s\n' "$parsed" | head -n 1)"
COUNTER="$(printf '%s\n' "$parsed" | tail -n 1)"
[ -n "$STOP_ACTIVE" ] || STOP_ACTIVE=0

# Detect project type; only set a command that actually exists (Codex 9, S5, S6).
TEST_CMD=""
LINT_CMD=""
TYPE_CMD=""
if [ -f "package.json" ]; then
  # Read package.json scripts structurally (S5), not by grepping the raw file.
  if python3 -c 'import json,sys; sys.exit(0 if "test" in (json.load(open("package.json")).get("scripts") or {}) else 1)' 2>/dev/null; then
    TEST_CMD="npm test"
  fi
  if python3 -c 'import json,sys; sys.exit(0 if "lint" in (json.load(open("package.json")).get("scripts") or {}) else 1)' 2>/dev/null; then
    LINT_CMD="npm run lint"
  fi
  # Only typecheck with the project's own tsc (S6 — no deprecated npx flag,
  # no network install).
  [ -x "node_modules/.bin/tsc" ] && TYPE_CMD="./node_modules/.bin/tsc --noEmit"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
  if [ -d "tests" ] || { [ -f "pyproject.toml" ] && grep -q "pytest" pyproject.toml 2>/dev/null; }; then
    TEST_CMD="python3 -m pytest"
  fi
  if command -v ruff &>/dev/null; then
    LINT_CMD="ruff check ."
  elif command -v flake8 &>/dev/null; then
    LINT_CMD="flake8"
  fi
  if command -v mypy &>/dev/null && [ -f "pyproject.toml" ]; then
    TYPE_CMD="mypy ."
  fi
elif [ -f "Cargo.toml" ]; then
  TEST_CMD="cargo test"
  LINT_CMD="cargo clippy -- -D warnings"
  TYPE_CMD="cargo check"
else
  exit 0  # Unknown project type — nothing to verify.
fi

FAILED=0
run_check() {
  local label="$1" cmd="$2" out
  [ -n "$cmd" ] || return 0
  # Intentional word-splitting: $cmd is a fixed command string with flags.
  # shellcheck disable=SC2086
  if ! out="$($cmd 2>&1)"; then
    {
      echo "BLOCK: $label failed. Run: $cmd"
      printf '%s\n' "$out" | tail -n 20
      echo ""
    } >&2
    FAILED=1
  fi
}

run_check "Typecheck" "$TYPE_CMD"
run_check "Tests" "$TEST_CMD"
run_check "Lint" "$LINT_CMD"

if [ "$FAILED" -eq 0 ]; then
  [ -n "$COUNTER" ] && rm -f "$COUNTER"   # green run resets the loop counter
  exit 0
fi

# Guard 1: honor stop_hook_active — a retried, still-red stop warn-allows.
if [ "$STOP_ACTIVE" -eq 1 ]; then
  echo "WARNING: checks still failing after a retry; allowing stop to prevent a loop." >&2
  exit 0
fi

# Guard 2: per-(session, project) block counter (last 10 minutes). Skipped when
# the state dir was rejected as insecure (COUNTER empty) — Guard 1 still applies.
if [ -n "$COUNTER" ]; then
  now="$(date +%s)"
  recent_blocks=0
  kept=""
  if [ -f "$COUNTER" ]; then
    while IFS= read -r ts; do
      # Ignore blank/non-numeric lines so a tampered counter can't crash arithmetic.
      case "$ts" in
        ''|*[!0-9]*) continue ;;
      esac
      if [ "$(( now - ts ))" -lt 600 ]; then
        recent_blocks="$(( recent_blocks + 1 ))"
        kept="$kept$ts
"
      fi
    done < "$COUNTER"
  fi
  if [ "$recent_blocks" -ge 2 ]; then
    echo "WARNING: this session has been blocked repeatedly; allowing stop to prevent a loop (counter guard)." >&2
    exit 0
  fi
  # Prune expired entries and append this block in one rewrite.
  printf '%s%s\n' "$kept" "$now" > "$COUNTER"
fi

echo "Fix all issues above before completing. The hook re-runs on your next stop attempt." >&2
exit 2
