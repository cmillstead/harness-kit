#!/usr/bin/env bash
# Smoke test: install the harness into throwaway repos and assert the git hooks
# and the Claude Code hooks behave as designed. Runnable locally:
#   bash tests/smoke.sh
#
# The internal HARNESS_KIT_HOOK_MODE seam forces the install path so results are
# deterministic: this script defaults it to "direct" (raw git hooks); CI's
# smoke-precommit job exports "precommit" to exercise the framework path. Both
# paths invoke the same scripts, so the behavioral assertions are identical.
# Every assertion checks an exit code AND a message.

set -uo pipefail

# Hermeticity (R3-1): neutralize any user/global/system git config — including a
# core.hooksPath the pre-commit framework would refuse to install over — so the
# test does not depend on the runner's environment. Exported, so sub-repos and
# `bash install.sh` inherit it. This replaces the old per-repo core.hooksPath pin
# (which is incompatible with pre-commit's install).
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

HARNESS_KIT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1"; fail=$((fail + 1)); }
run_or_die() {
    local label="$1"; shift
    if ! "$@" >/dev/null 2>&1; then
        printf 'FATAL: %s failed\n' "$label"
        exit 1
    fi
}

cd "$WORK" || exit 1
git init -q
git config user.email "smoke@test.local"
git config user.name "Smoke Test"

# Deterministic install path (R5): default to raw git hooks so assertions never
# depend on whether pre-commit happens to be on the runner. CI's precommit job
# overrides this by exporting HARNESS_KIT_HOOK_MODE=precommit before calling us.
export HARNESS_KIT_HOOK_MODE="${HARNESS_KIT_HOOK_MODE:-direct}"
run_or_die "install.sh" bash "$HARNESS_KIT/install.sh"

# --- Completeness: install created the full expected file set ---
missing=""
for f in AGENTS.md CLAUDE.md .pre-commit-config.yaml .gitignore \
         .cursor/rules/harness.md \
         docs/golden-principles.md docs/harness-philosophy.md docs/code-style.md \
         docs/decision-record-template.md docs/eval-template.md \
         docs/escape-hatch-audit.md docs/context-inheritance-audit.md \
         skills/review.md .claude/skills/review/SKILL.md \
         .claude/hooks/stop-verify.sh .claude/hooks/pre-completion-checklist.py \
         .claude/hooks/settings-snippet.json \
         .harness/hooks/no-mocks.sh .harness/hooks/pre-commit-verify.sh \
         .harness/hooks/post-commit-cleanup.sh; do
    [ -e "$f" ] || missing="$missing $f"
done
if [ -z "$missing" ]; then
    ok "completeness: all expected files present after install"
else
    bad "completeness: missing:$missing"
fi

# --- SKILL.md is a valid Claude Code skill (frontmatter first) ---
if [ -f .claude/skills/review/SKILL.md ] && head -1 .claude/skills/review/SKILL.md | grep -q '^---'; then
    ok "skill: .claude/skills/review/SKILL.md exists and starts with frontmatter"
else
    bad "skill: SKILL.md missing or lacks '---' frontmatter"
fi

# --- settings-snippet parses and has the three matcher-groups ---
groups="$(python3 -c 'import json;h=json.load(open(".claude/hooks/settings-snippet.json"))["hooks"];print("ok" if all(k in h for k in ("Stop","PreToolUse","PostToolUse")) else "no")' 2>/dev/null)"
if [ "$groups" = "ok" ]; then
    ok "settings: snippet parses with Stop + PreToolUse + PostToolUse groups"
else
    bad "settings: snippet missing a matcher-group (got: $groups)"
fi

# --- Idempotency: a second install exits 0 and changes no file CONTENT or MODE ---
# R4/R3-4: hash content (sha256) AND permission bits, and crucially INCLUDE the
# installed git hooks (.git/hooks) while pruning only volatile git internals
# (index/logs/refs/objects/HEAD/etc.) — the round-2 snapshot pruned all of .git,
# so a rewritten hook was invisible. Pure python stdlib avoids the `ls | awk`
# pattern that ShellCheck flags as SC2012 (R4-6: this line must not begin with a
# `#`+`shellcheck` token, or it parses as a directive); os.walk/os.stat behave
# identically on BSD (macOS) and GNU.
snapshot() {
    # Recursive content+mode+symlink snapshot of ${1:-$PWD}. Reused for the
    # idempotency check (whole repo) AND the external-hooksPath containment check.
    python3 - "${1:-$PWD}" <<'PY'
import hashlib, os, stat, sys
root = sys.argv[1]
rows = []
for dirpath, dirnames, filenames in os.walk(root):
    rel = os.path.relpath(dirpath, root)
    parts = [] if rel == "." else rel.split(os.sep)
    if parts and parts[0] == ".git":
        if len(parts) == 1:
            # At .git root: descend ONLY into hooks; skip .git's own volatile files.
            dirnames[:] = [d for d in dirnames if d == "hooks"]
            continue
        # Deeper than .git only ever reached under .git/hooks (others pruned above).
    for name in sorted(filenames):
        path = os.path.join(dirpath, name)
        relp = os.path.relpath(path, root)
        try:
            info = os.lstat(path)
        except FileNotFoundError:
            continue
        mode = stat.S_IMODE(info.st_mode)
        if stat.S_ISLNK(info.st_mode):
            digest = "symlink:" + os.readlink(path)
        else:
            with open(path, "rb") as handle:
                digest = hashlib.sha256(handle.read()).hexdigest()
        rows.append("%s %o %s" % (relp, mode, digest))
print("\n".join(sorted(rows)))
PY
}
before="$(snapshot)"
if bash "$HARNESS_KIT/install.sh" >/dev/null 2>&1; then
    after="$(snapshot)"
    if [ "$before" = "$after" ]; then
        ok "idempotency: second install changes no file content or mode (incl. .git/hooks)"
    else
        bad "idempotency: second install changed file content/mode"
    fi
else
    bad "idempotency: second install did not exit 0"
fi

# Baseline commit (no marker -> docs-only; --no-verify keeps setup hook-independent).
git add -A
run_or_die "baseline commit" git commit -q --no-verify -m "chore: install harness"

# --- Test A: no-mocks blocks a mocked test file (no marker -> verify skips) ---
mkdir -p tests
printf 'from unittest.mock import MagicMock\n' > tests/test_sample.py  # mock-ok: fixture data testing the no-mocks hook, not a real mock
git add tests/test_sample.py
a_out="$(git commit -q -m "test: mocked test file" 2>&1)"
a_rc=$?
if [ "$a_rc" -ne 0 ] && printf '%s' "$a_out" | grep -q "BLOCKED: Mock usage"; then
    ok "A: no-mocks blocked a mocked test file with the expected banner"
else
    bad "A: expected non-zero exit + 'BLOCKED: Mock usage' (rc=$a_rc)"
fi
git reset -q
rm -f tests/test_sample.py

# --- Test B: missing stamp blocks when a project marker exists ---
printf '{"name":"demo"}\n' > package.json
printf 'console.log("x");\n' > app.js
rm -f .harness-verified
git add -A
b_out="$(git commit -q -m "feat: change without stamp" 2>&1)"
b_rc=$?
if [ "$b_rc" -ne 0 ] && printf '%s' "$b_out" | grep -q "BLOCKED: No verification stamp"; then
    ok "B: verify hook blocked a commit with no stamp"
else
    bad "B: expected non-zero exit + 'BLOCKED: No verification stamp' (rc=$b_rc)"
fi

# --- Test C: a fresh stamp allows the commit, post-commit deletes it ---
touch .harness-verified
if git commit -q -m "feat: change with fresh stamp" 2>/dev/null; then
    ok "C: commit succeeded with a fresh stamp"
else
    bad "C: commit should succeed with a fresh stamp"
fi
if [ -f .harness-verified ]; then
    bad "C: post-commit hook should delete the stamp"
else
    ok "C: post-commit hook deleted the stamp"
fi

# --- Stale stamp (> 30 min) is rejected ---
echo stale > f_stale.txt
git add f_stale.txt
touch -t 202001010000 .harness-verified
s_out="$(git commit -q -m "feat: stale stamp" 2>&1)"
s_rc=$?
if [ "$s_rc" -ne 0 ] && printf '%s' "$s_out" | grep -q "stale"; then
    ok "stale: a >30m stamp is rejected"
else
    bad "stale: expected block on a stale stamp (rc=$s_rc)"
fi

# --- Future-dated stamp is rejected (Codex 12) ---
echo future > f_future.txt
git add f_future.txt
touch -t 203012312359 .harness-verified
fu_out="$(git commit -q -m "feat: future stamp" 2>&1)"
fu_rc=$?
if [ "$fu_rc" -ne 0 ] && printf '%s' "$fu_out" | grep -q "future"; then
    ok "future: a future-dated stamp is rejected"
else
    bad "future: expected block on a future stamp (rc=$fu_rc)"
fi

# --- Test D: docs-only repo commits without a stamp ---
rm -f .harness-verified
git rm -q package.json app.js
printf '# notes\n' > NOTES.md
git add -A
if git commit -q -m "docs: notes" 2>/dev/null; then
    ok "D: docs-only commit succeeded without a stamp"
else
    bad "D: docs-only commit should succeed without a stamp"
fi

# --- stop-verify: first stop blocks (2); stop_hook_active warns; counter guard warns ---
# The hook cd's into CLAUDE_PROJECT_DIR (R5/Codex 8), so we pass it explicitly
# instead of relying on the caller's cwd. The fixture's test fails deterministically.
fixture="$(mktemp -d)"
printf '{"scripts":{"test":"exit 1"}}\n' > "$fixture/package.json"

sv_sess="smoke-stop-$$-${RANDOM}"
sv_out="$(printf '{"stop_hook_active":false,"session_id":"%s"}' "$sv_sess" \
    | CLAUDE_PROJECT_DIR="$fixture" bash "$HARNESS_KIT/hooks/stop-verify.sh" 2>&1)"
sv_rc=$?
if [ "$sv_rc" -eq 2 ] && printf '%s' "$sv_out" | grep -q "BLOCK:"; then
    ok "stop-verify: first stop blocks with exit 2 + BLOCK banner"
else
    bad "stop-verify: expected exit 2 + BLOCK (rc=$sv_rc)"
fi

# Guard 1: stop_hook_active=true warn-allows (exit 0) before the counter is touched.
sva_out="$(printf '{"stop_hook_active":true,"session_id":"%s-active"}' "$sv_sess" \
    | CLAUDE_PROJECT_DIR="$fixture" bash "$HARNESS_KIT/hooks/stop-verify.sh" 2>&1)"
sva_rc=$?
if [ "$sva_rc" -eq 0 ] && printf '%s' "$sva_out" | grep -q "after a retry"; then
    ok "stop-verify: stop_hook_active warns and allows (exit 0)"
else
    bad "stop-verify: expected exit 0 + retry WARNING (rc=$sva_rc)"
fi

# Guard 2 (R2): same session, stop_hook_active always false. Blocks 1 and 2 must
# each exit 2 (asserted); block 3 warn-allows because >= 2 recent blocks are on
# record for this (session, project).
loop_sess="smoke-loop-$$-${RANDOM}"
loop_payload="$(printf '{"stop_hook_active":false,"session_id":"%s"}' "$loop_sess")"

printf '%s' "$loop_payload" | CLAUDE_PROJECT_DIR="$fixture" bash "$HARNESS_KIT/hooks/stop-verify.sh" >/dev/null 2>&1
loop1_rc=$?
if [ "$loop1_rc" -eq 2 ]; then
    ok "stop-verify: counter block 1 exits 2"
else
    bad "stop-verify: counter block 1 expected exit 2 (rc=$loop1_rc)"
fi

printf '%s' "$loop_payload" | CLAUDE_PROJECT_DIR="$fixture" bash "$HARNESS_KIT/hooks/stop-verify.sh" >/dev/null 2>&1
loop2_rc=$?
if [ "$loop2_rc" -eq 2 ]; then
    ok "stop-verify: counter block 2 exits 2"
else
    bad "stop-verify: counter block 2 expected exit 2 (rc=$loop2_rc)"
fi

loop_out="$(printf '%s' "$loop_payload" | CLAUDE_PROJECT_DIR="$fixture" bash "$HARNESS_KIT/hooks/stop-verify.sh" 2>&1)"
loop_rc=$?
if [ "$loop_rc" -eq 0 ] && printf '%s' "$loop_out" | grep -q "counter guard"; then
    ok "stop-verify: counter guard warn-allows the 3rd block in one session (R2)"
else
    bad "stop-verify: expected exit 0 + 'counter guard' on 3rd block (rc=$loop_rc)"
fi
rm -rf "$fixture"

# --- Test E: checklist gates at PreToolUse, records at PostToolUse (success-only) ---
py_hook="$HARNESS_KIT/hooks/pre-completion-checklist.py"
printf '{"name":"demo"}\n' > package.json   # marker so the gate engages

# PostToolUse fires ONLY on tool success (verified protocol fact), so record
# payloads carry no tool_response. The hook keys state on session_id + project
# root; we set CLAUDE_PROJECT_DIR="$WORK" so record and gate resolve to the same
# root deterministically (R3-3) without depending on the git-toplevel fallback.
record() {   # session, command-string
    printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$WORK" "$2" \
        | CLAUDE_PROJECT_DIR="$WORK" python3 "$py_hook" >/dev/null 2>&1
}
gate_out() { # session -> gate stdout (empty means allow)
    printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$1" "$WORK" \
        | CLAUDE_PROJECT_DIR="$WORK" python3 "$py_hook"
}

sess_unverified="smoke-$$-${RANDOM}-unverified"
if printf '%s' "$(gate_out "$sess_unverified")" | grep -q '"permissionDecision": *"deny"'; then
    ok "E: unverified session -> PreToolUse deny"
else
    bad "E: expected a PreToolUse deny"
fi

sess_verified="smoke-$$-${RANDOM}-verified"
record "$sess_verified" "npm test"
record "$sess_verified" "npm run lint"
if [ -z "$(gate_out "$sess_verified")" ]; then
    ok "E: verified session (PostToolUse-recorded) -> commit allowed"
else
    bad "E: expected allow after recording test + lint"
fi

# --- R1: should_record rejects shell-metachar / non-anchored "verification" cmds ---
# Each string below LOOKS like a test run but must NOT be recorded as one (|| and
# a leading env-assignment carry metachars; echo is not an approved verifier), so
# with only a real lint recorded the gate must still DENY.
neg_i=0
for bogus in 'npm test || true' 'echo npm test' 'FOO=bar npm test'; do
    neg_i=$((neg_i + 1))
    neg_sess="smoke-$$-${RANDOM}-neg$neg_i"
    record "$neg_sess" "npm run lint"   # a real lint IS recorded
    record "$neg_sess" "$bogus"         # this must NOT count as a test
    if printf '%s' "$(gate_out "$neg_sess")" | grep -q '"permissionDecision": *"deny"'; then
        ok "R1: non-anchored command not recorded, gate still denies: $bogus"
    else
        bad "R1: '$bogus' was wrongly accepted as a test verification"
    fi
done

# --- R4-1: project root is resolved from the EVENT cwd, not a stale CLAUDE_PROJECT_DIR ---
# Parameterized helpers so we can vary cwd and CLAUDE_PROJECT_DIR independently.
record_in() {  # session, cwd, projdir, command
    printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2" "$4" \
        | CLAUDE_PROJECT_DIR="$3" python3 "$py_hook" >/dev/null 2>&1
}
gate_in() {    # session, cwd, projdir -> gate stdout
    printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$1" "$2" \
        | CLAUDE_PROJECT_DIR="$3" python3 "$py_hook"
}

repo2="$(mktemp -d)"
( cd "$repo2" && git init -q && printf '{"name":"r2"}\n' > package.json )

# (a) A commit from a project SUBDIRECTORY is still gated (root resolves to the repo top).
mkdir -p "$WORK/subpkg"
sub_sess="smoke-$$-${RANDOM}-sub"
if printf '%s' "$(gate_in "$sub_sess" "$WORK/subpkg" "$WORK")" | grep -q '"permissionDecision": *"deny"'; then
    ok "R4-1a: commit from a subdirectory is still gated"
else
    bad "R4-1a: a subdirectory commit was not gated"
fi

# (b) A verification run in repo2 must NOT authorize repo1, even though
#     CLAUDE_PROJECT_DIR still names repo1 (cwd wins).
xr_sess="smoke-$$-${RANDOM}-xrepo"
record_in "$xr_sess" "$repo2" "$WORK" "npm test"
record_in "$xr_sess" "$repo2" "$WORK" "npm run lint"
if printf '%s' "$(gate_in "$xr_sess" "$WORK" "$WORK")" | grep -q '"permissionDecision": *"deny"'; then
    ok "R4-1b: a verification in a second repo does not authorize the first"
else
    bad "R4-1b: repo2 verification wrongly authorized repo1"
fi

# (c) A verification in repo1 must NOT be consumed by a commit in repo2.
xr2_sess="smoke-$$-${RANDOM}-xrepo2"
record_in "$xr2_sess" "$WORK" "$WORK" "npm test"
record_in "$xr2_sess" "$WORK" "$WORK" "npm run lint"
if printf '%s' "$(gate_in "$xr2_sess" "$repo2" "$WORK")" | grep -q '"permissionDecision": *"deny"'; then
    ok "R4-1c: a commit in the second repo does not consume the first repo's state"
else
    bad "R4-1c: repo1 state leaked into repo2"
fi
rm -rf "$repo2" "$WORK/subpkg"

# --- R4-4: an insecure state dir -> the gate FAILS CLOSED (deny decision) ---
# Redirect the hook's temp base with TMPDIR and pre-plant the per-user state dir
# as a symlink; state_dir() must raise and the gate must emit a deny.
bad_tmp="$(mktemp -d)"
ln -s /tmp "$bad_tmp/claude-harness-$(id -u)"
r44_out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"smoke-r44","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$WORK" \
    | TMPDIR="$bad_tmp" CLAUDE_PROJECT_DIR="$WORK" python3 "$py_hook")"
if printf '%s' "$r44_out" | grep -q '"permissionDecision": *"deny"'; then
    ok "R4-4: insecure state dir -> gate denies (fail-closed)"
else
    bad "R4-4: gate should fail closed on an insecure state dir"
fi
rm -rf "$bad_tmp"

# --- Chaining (R3-4): a foreign hook is preserved (content+mode), the wrapper is
#     marked, the installer exits 0, and a commit is blocked by the chained hook. ---
# Force raw-hook mode so chaining is exercised regardless of the outer mode.
chain="$(mktemp -d)"
(
    cd "$chain" || exit 1
    git init -q
    git config user.email a@b.c
    git config user.name t
    mkdir -p .git/hooks
    printf '#!/usr/bin/env bash\necho "PREEXISTING HOOK RAN" >&2\nexit 1\n' > .git/hooks/pre-commit
    chmod 755 .git/hooks/pre-commit
    HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" >/dev/null 2>&1
)
ch_install_rc=$?
ch_hd="$chain/.git/hooks"

if [ "$ch_install_rc" -eq 0 ]; then
    ok "chaining: installer exits 0 over a pre-existing foreign hook"
else
    bad "chaining: installer exit $ch_install_rc over a foreign hook"
fi

if [ -f "$ch_hd/pre-commit.harness-preserved" ] \
   && grep -q "PREEXISTING HOOK RAN" "$ch_hd/pre-commit.harness-preserved" \
   && [ -x "$ch_hd/pre-commit.harness-preserved" ]; then
    ok "chaining: original hook preserved with its content and executable mode"
else
    bad "chaining: preserved hook missing, wrong content, or not executable"
fi

if [ -f "$ch_hd/pre-commit" ] && grep -Fxq '# harness-kit hook' "$ch_hd/pre-commit"; then
    ok "chaining: active pre-commit carries the harness-kit marker"
else
    bad "chaining: active pre-commit is missing the harness-kit marker"
fi

ch_out="$(cd "$chain" && git add -A && git commit -q -m "blocked by chained hook" 2>&1)"
ch_rc=$?
if [ "$ch_rc" -ne 0 ]; then
    ok "chaining: commit blocked by the chained hook (rc=$ch_rc)"
else
    bad "chaining: commit should have been blocked by the chained hook"
fi
if printf '%s' "$ch_out" | grep -q "PREEXISTING HOOK RAN"; then
    ok "chaining: preserved hook executed (its output appeared)"
else
    bad "chaining: preserved hook output did not appear"
fi
rm -rf "$chain"

# --- Containment (a) / R5-1: installing from a LINKED WORKTREE is REFUSED. The
#     hooks dir is shared via git-common-dir, but the harness wrappers invoke
#     worktree-local paths, so wiring them here would break the primary and sibling
#     worktrees. Assert: NOT-active banner, the shared hooks dir is untouched, and a
#     later PRIMARY-worktree commit still succeeds. ---
wtmain="$(mktemp -d)"
(
    cd "$wtmain" || exit 1
    git init -q
    git config user.email a@b.c
    git config user.name t
    printf '{"name":"demo"}\n' > package.json
    git add -A && git commit -q -m init
)
shared_hooks="$wtmain/.git/hooks"
wtlinked="$(mktemp -d)"; rmdir "$wtlinked"   # need a non-existent path for `worktree add`
( cd "$wtmain" && git worktree add -q "$wtlinked" >/dev/null 2>&1 )
sh_before="$(snapshot "$shared_hooks")"      # snapshot AFTER worktree add, before install
wt_out="$(cd "$wtlinked" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" 2>&1)"
wt_rc=$?
if [ "$wt_rc" -eq 0 ] && printf '%s' "$wt_out" | grep -q "NOT active" \
   && printf '%s' "$wt_out" | grep -q "LINKED git worktree"; then
    ok "R5-1: linked-worktree install refuses hook wiring (NOT-active banner)"
else
    bad "R5-1: linked-worktree install did not report the worktree refusal (rc=$wt_rc)"
fi
sh_after="$(snapshot "$shared_hooks")"
if [ "$sh_before" = "$sh_after" ]; then
    ok "R5-1: shared common-dir hooks dir left untouched by the worktree install"
else
    bad "R5-1: worktree install modified the shared hooks dir"
fi
prim_rc=0
( cd "$wtmain" && git commit -q --allow-empty -m after ) || prim_rc=$?
if [ "$prim_rc" -eq 0 ]; then
    ok "R5-1: a subsequent primary-worktree commit is unaffected"
else
    bad "R5-1: primary-worktree commit broke after a linked-worktree install (rc=$prim_rc)"
fi
( cd "$wtmain" && git worktree remove --force "$wtlinked" >/dev/null 2>&1 )
rm -rf "$wtmain" "$wtlinked"

# --- Containment (b): an external core.hooksPath is REFUSED, and the external
#     directory is neither created nor modified. A recursive content+mode snapshot
#     (reusing snapshot()) detects truncation, chmod, or a newly-created file that a
#     bare "keep.txt exists && pre-commit absent" check would miss. ---
ext_repo="$(mktemp -d)"
ext_hooks="$(mktemp -d)"                       # pre-existing dir OUTSIDE any repo
printf 'sentinel\n' > "$ext_hooks/keep.txt"
chmod 0700 "$ext_hooks/keep.txt"               # a distinctive mode the snapshot will catch
(
    cd "$ext_repo" && git init -q && git config user.email a@b.c && git config user.name t
    git config core.hooksPath "$ext_hooks"
)
ext_before="$(snapshot "$ext_hooks")"
ext_rc=0
( cd "$ext_repo" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" >/dev/null 2>&1 ) || ext_rc=$?
ext_after="$(snapshot "$ext_hooks")"
if [ "$ext_rc" -ne 0 ] && [ "$ext_before" = "$ext_after" ]; then
    ok "containment: external core.hooksPath refused; external dir byte-for-byte unchanged"
else
    bad "containment: external hooksPath not refused or its dir changed (rc=$ext_rc)"
fi
rm -rf "$ext_repo" "$ext_hooks"

# --- R5-2: a marker-owned but NON-EXECUTABLE post-commit (a prior half-install, the
#     reachable trigger for the old partial-install bug) is repaired within the
#     transaction; the install succeeds and BOTH hooks end up active + executable. ---
nx="$(mktemp -d)"
(
    cd "$nx" && git init -q && git config user.email a@b.c && git config user.name t
    printf '{"name":"demo"}\n' > package.json
    git add -A && git commit -q -m init
    printf '#!/usr/bin/env bash\n# harness-kit hook\n' > .git/hooks/post-commit
    chmod -x .git/hooks/post-commit
)
nx_out="$(cd "$nx" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" 2>&1)"
nx_rc=$?
if [ "$nx_rc" -eq 0 ] && printf '%s' "$nx_out" | grep -q "installed successfully" \
   && [ -x "$nx/.git/hooks/pre-commit" ] && [ -x "$nx/.git/hooks/post-commit" ]; then
    ok "R5-2: non-executable marker hook repaired in-transaction; both hooks executable"
else
    bad "R5-2: non-exec marker not repaired or install did not report success (rc=$nx_rc)"
fi
rm -rf "$nx"

# --- R6: a foreign .pre-commit-config.yaml -> installer exits 0, leaves the config
#     untouched, and the banner truthfully reports hooks inactive. ---
# Auto mode (env -u) so the foreign-config branch engages instead of a forced path.
fc="$(mktemp -d)"
( cd "$fc" && git init -q && git config user.email a@b.c && git config user.name t )
# A pre-existing, non-harness pre-commit config triggers CONFIG_FOREIGN.
printf 'repos:\n  - repo: local\n    hooks:\n      - id: my-own\n        name: my own\n        entry: "true"\n        language: system\n' > "$fc/.pre-commit-config.yaml"
cp "$fc/.pre-commit-config.yaml" "$fc/.cfg.orig"
fc_mode_before="$(python3 -c 'import os,stat,sys;print(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$fc/.pre-commit-config.yaml")"
fc_out="$(cd "$fc" && env -u HARNESS_KIT_HOOK_MODE bash "$HARNESS_KIT/install.sh" 2>&1)"
fc_rc=$?
fc_mode_after="$(python3 -c 'import os,stat,sys;print(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$fc/.pre-commit-config.yaml")"

if [ "$fc_rc" -eq 0 ]; then
    ok "R6: installer exits 0 with a foreign config (no false-fatal)"
else
    bad "R6: installer expected exit 0 over a foreign config (rc=$fc_rc)"
fi
if printf '%s' "$fc_out" | grep -q "NOT active"; then
    ok "R6: foreign pre-commit config -> banner reports hooks NOT active"
else
    bad "R6: expected a 'NOT active' banner for a foreign config"
fi
if printf '%s' "$fc_out" | grep -q "installed successfully"; then
    bad "R6: banner falsely claimed 'installed successfully' with a foreign config"
else
    ok "R6: banner does not claim success when hooks are inactive"
fi
if cmp -s "$fc/.pre-commit-config.yaml" "$fc/.cfg.orig" && [ "$fc_mode_before" = "$fc_mode_after" ]; then
    ok "R6: foreign .pre-commit-config.yaml left unmodified (content + mode)"
else
    bad "R6: foreign config was modified by the installer"
fi
rm -rf "$fc"

# --- R4-3: a near-miss config (mentions all 3 harness hook paths but not
#     byte-identical — post-commit-cleanup registered at the wrong stage) is still
#     treated as foreign, so hooks stay inactive. A string-grep would accept it. ---
pc="$(mktemp -d)"
( cd "$pc" && git init -q && git config user.email a@b.c && git config user.name t )
printf 'repos:\n  - repo: local\n    hooks:\n      - id: h\n        name: h\n        entry: .harness/hooks/no-mocks.sh .harness/hooks/pre-commit-verify.sh .harness/hooks/post-commit-cleanup.sh\n        language: system\n        stages: [pre-commit]\n' > "$pc/.pre-commit-config.yaml"
pc_out="$(cd "$pc" && env -u HARNESS_KIT_HOOK_MODE bash "$HARNESS_KIT/install.sh" 2>&1)"
if printf '%s' "$pc_out" | grep -q "NOT active"; then
    ok "R4-3: near-miss config (all 3 strings, wrong stage) treated as foreign"
else
    bad "R4-3: near-miss config was wrongly accepted as the harness config"
fi
rm -rf "$pc"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
