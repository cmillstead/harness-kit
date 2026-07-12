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

# Hermeticity (Codex ~L22): keep ALL hook state INSIDE $WORK. The checklist and
# stop-verify hooks derive their per-user state dir from tempfile.gettempdir()
# (which honors $TMPDIR), so without this they leave a claude-harness-$(id -u)
# dir under the real system temp after the run. Pointing $TMPDIR at a subdir of
# $WORK means every hook-written state file AND every `mktemp -d` fixture below
# lands under $WORK and is removed by the EXIT trap. Sub-repo fixtures each run
# their own `git init`, so nesting them under $WORK's repo is inert (git resolves
# the nearest .git). Fixtures that need an INSECURE base override $TMPDIR locally.
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"

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
    # Codex ~L99: emit DIRECTORY entries (path + mode + "dir") and symlink-to-dir
    # entries (path + target) as well as files, so a directory-mode change or a
    # swapped symlink-to-dir is caught by the containment/idempotency diffs — not
    # just file content/mode. Pure python stdlib (os.walk/os.lstat) is identical
    # on BSD (macOS) and GNU. os.walk does NOT follow symlinks (followlinks=False),
    # so a symlink-to-dir is recorded by target and never recursed into.
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
    for name in sorted(dirnames):
        path = os.path.join(dirpath, name)
        relp = os.path.relpath(path, root)
        try:
            info = os.lstat(path)
        except FileNotFoundError:
            continue
        mode = stat.S_IMODE(info.st_mode)
        if stat.S_ISLNK(info.st_mode):
            rows.append("%s %o symlink:%s" % (relp, mode, os.readlink(path)))
        else:
            rows.append("%s %o dir" % (relp, mode))
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

# --- CLAUDE.md pre-existing message-only behavior (installer step 6). Each
#     fixture is a standalone sandbox repo (mktemp -d + git init), not $WORK, so
#     it does not disturb the completeness/idempotency state above. ---

# Assertion 1: a pre-existing CLAUDE.md WITHOUT an AGENTS.md reference is
# preserved byte-for-byte (message-only: never mutate authored content), and the
# installer prints the actionable AGENTS.md pointer line plus the nudge to add it.
cm_noref="$(mktemp -d)"
(
    cd "$cm_noref" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    printf '# My rules\ndo the thing\n' > CLAUDE.md
)
cp "$cm_noref/CLAUDE.md" "$cm_noref/.claude.orig"
cm_noref_out="$(cd "$cm_noref" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" 2>&1)"
cm_noref_rc=$?
if [ "$cm_noref_rc" -eq 0 ] && cmp -s "$cm_noref/CLAUDE.md" "$cm_noref/.claude.orig" \
   && printf '%s' "$cm_noref_out" | grep -qF "Read AGENTS.md for project conventions" \
   && printf '%s' "$cm_noref_out" | grep -q "add this line"; then
    ok "CLAUDE.md: pre-existing file without an AGENTS.md ref preserved byte-for-byte; pointer nudge printed"
else
    bad "CLAUDE.md: no-ref case failed (rc=$cm_noref_rc)"
fi
rm -rf "$cm_noref"

# Assertion 2: a pre-existing CLAUDE.md WITH an AGENTS.md reference is preserved
# byte-for-byte, the installer reports the idempotent skip message, and does NOT
# print the nag to add the pointer line.
cm_ref="$(mktemp -d)"
(
    cd "$cm_ref" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    printf '# My CLAUDE.md\nRead AGENTS.md for project conventions, boundaries, and commands.\n' > CLAUDE.md
)
cp "$cm_ref/CLAUDE.md" "$cm_ref/.claude.orig"
cm_ref_out="$(cd "$cm_ref" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" 2>&1)"
cm_ref_rc=$?
if [ "$cm_ref_rc" -eq 0 ] && cmp -s "$cm_ref/CLAUDE.md" "$cm_ref/.claude.orig" \
   && printf '%s' "$cm_ref_out" | grep -q "references AGENTS.md" \
   && ! printf '%s' "$cm_ref_out" | grep -q "add this line"; then
    ok "CLAUDE.md: pre-existing file with an AGENTS.md ref preserved byte-for-byte; skip message printed, no nag"
else
    bad "CLAUDE.md: with-ref case failed (rc=$cm_ref_rc)"
fi
rm -rf "$cm_ref"

# Assertion 3: no pre-existing CLAUDE.md -> created with the AGENTS.md pointer
# line. The completeness check above only asserts file EXISTENCE; this asserts
# CONTENT, which is the create-path behavior this task's fix must not disturb.
cm_new="$(mktemp -d)"
( cd "$cm_new" && git init -q && git config user.email a@b.c && git config user.name t )
( cd "$cm_new" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" ) >/dev/null 2>&1
cm_new_rc=$?
if [ "$cm_new_rc" -eq 0 ] && [ -f "$cm_new/CLAUDE.md" ] \
   && grep -qF "Read AGENTS.md for project conventions" "$cm_new/CLAUDE.md"; then
    ok "CLAUDE.md: no pre-existing file -> created with the AGENTS.md pointer line"
else
    bad "CLAUDE.md: create path missing the AGENTS.md pointer line (rc=$cm_new_rc)"
fi
rm -rf "$cm_new"

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

# --- no-mocks FX3 coverage. Each fixture drives no-mocks.sh DIRECTLY against a
# throwaway repo's staged index (like the stop-verify/checklist fixtures), so the
# smoke's OWN commit never scans these generated files. The mock-pattern strings
# below are split with an empty shell-quote (Magic''Mock, jest.moc''k) so the
# literal pattern never appears on a smoke.sh line — the harness's own no-mocks
# thus does not flag smoke.sh, so NO second exemption annotation is needed —
# while the generated fixture file still contains the intact pattern for the
# sub-repo's hook to detect.

# (FX3) rename+modify: `git mv` a clean test file AND add a mock line in the same
# index. --diff-filter=ACMR must include the renamed (R) path so it is scanned.
nm_rn="$(mktemp -d)"
(
    cd "$nm_rn" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    mkdir -p tests
    printf 'def test_ok():\n    assert True\n    assert 1 == 1\n    assert 2 == 2\n    assert 3 == 3\n' > tests/test_orig.py
    git add -A && git commit -q --no-verify -m init
    git mv tests/test_orig.py tests/test_renamed.py
    printf 'x = Magic''Mock()\n' >> tests/test_renamed.py
    git add tests/test_renamed.py
)
nm_rn_out="$(cd "$nm_rn" && bash "$HARNESS_KIT/hooks/no-mocks.sh" 2>&1)"
nm_rn_rc=$?
if [ "$nm_rn_rc" -ne 0 ] && printf '%s' "$nm_rn_out" | grep -q "BLOCKED: Mock usage"; then
    ok "no-mocks: rename+modify (--diff-filter ACMR) blocks an added mock in a renamed file"
else
    bad "no-mocks: rename+modify not blocked (rc=$nm_rn_rc)"
fi
rm -rf "$nm_rn"

# (FX3) non-ASCII filename: NUL-delimited staged names (-z) so a UTF-8 path is
# passed verbatim to the per-file diff (core.quotepath would otherwise mangle it).
nm_ua="$(mktemp -d)"
(
    cd "$nm_ua" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    mkdir -p tests
    printf 'x = Magic''Mock()\n' > tests/tést.py
    git add -A
)
nm_ua_out="$(cd "$nm_ua" && bash "$HARNESS_KIT/hooks/no-mocks.sh" 2>&1)"
nm_ua_rc=$?
if [ "$nm_ua_rc" -ne 0 ] && printf '%s' "$nm_ua_out" | grep -q "BLOCKED: Mock usage"; then
    ok "no-mocks: non-ASCII filename (tests/tést.py) with a mock is blocked (-z NUL-delimited)"
else
    bad "no-mocks: non-ASCII filename not blocked (rc=$nm_ua_rc)"
fi
rm -rf "$nm_ua"

# (QA gap) a NON-Python mock pattern run through the live hook on macOS/BSD grep.
nm_js="$(mktemp -d)"
(
    cd "$nm_js" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    printf 'jest.moc''k("./dep");\n' > app.test.js
    git add -A
)
nm_js_out="$(cd "$nm_js" && bash "$HARNESS_KIT/hooks/no-mocks.sh" 2>&1)"
nm_js_rc=$?
if [ "$nm_js_rc" -ne 0 ] && printf '%s' "$nm_js_out" | grep -q "BLOCKED: Mock usage"; then
    ok "no-mocks: a JS mock pattern in a .test.js file is blocked"
else
    bad "no-mocks: JS mock pattern not blocked (rc=$nm_js_rc)"
fi
rm -rf "$nm_js"

# (FR2) enumeration failure: no-mocks must ABORT (nonzero exit + the
# enumeration-failure message), not silently scan an empty list, when its own
# `git diff --cached --name-only` call fails. We force that failure by pointing
# GIT_DIR at a real directory that is NOT a git repository: setting GIT_DIR
# disables git's upward repo *discovery* entirely, so the enumeration call fails
# deterministically on every platform. (An earlier GIT_CEILING_DIRECTORIES +
# bare-dir approach relied on discovery failing, which is environment-specific:
# on some Linux CI runners git still discovered an ancestor repo above /tmp,
# enumerated zero files, and exited 0 — the injection never fired. GIT_DIR
# removes that dependence on the surrounding filesystem.)
nm_noenum="$(mktemp -d)"
nm_noenum_gitdir="$(mktemp -d)"   # exists, but is not a git repository
nm_noenum_out="$(cd "$nm_noenum" && GIT_DIR="$nm_noenum_gitdir" bash "$HARNESS_KIT/hooks/no-mocks.sh" 2>&1)"
nm_noenum_rc=$?
if [ "$nm_noenum_rc" -ne 0 ] && printf '%s' "$nm_noenum_out" | grep -q "failed to enumerate staged files"; then
    ok "no-mocks: staged-file enumeration failure aborts (nonzero exit + message), not a silent no-op"
else
    bad "no-mocks: enumeration failure not handled (rc=$nm_noenum_rc)"
fi
rm -rf "$nm_noenum" "$nm_noenum_gitdir"

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

# --- stop-verify insecure state dir (the missing test that let a Tier-1 bug survive).
# Mirror the checklist's R4-4 fixture: point TMPDIR at a base where the per-user
# state dir is pre-planted as a SYMLINK, then drive a RED repo (test -> exit 1)
# with stop_hook_active:false. secure_state_dir() must reject the symlink so
# COUNTER stays empty and Guard 2 is skipped. Assert BOTH signals: exit 2 (first
# block still fires via Guard-less path) AND no file literally named `0` or `1`
# was created in the project dir — the pre-fix bug wrote junk COUNTER files there.
sv_bad_tmp="$(mktemp -d)"
ln -s /tmp "$sv_bad_tmp/claude-harness-$(id -u)"
sv_red="$(mktemp -d)"
printf '{"scripts":{"test":"exit 1"}}\n' > "$sv_red/package.json"
printf '{"stop_hook_active":false,"session_id":"smoke-sv-insecure"}' \
    | TMPDIR="$sv_bad_tmp" CLAUDE_PROJECT_DIR="$sv_red" bash "$HARNESS_KIT/hooks/stop-verify.sh" >/dev/null 2>&1
svbad_rc=$?
if [ "$svbad_rc" -eq 2 ] && [ ! -e "$sv_red/0" ] && [ ! -e "$sv_red/1" ]; then
    ok "stop-verify: insecure state dir -> exit 2, no junk 0/1 counter file (Guard 2 skipped)"
else
    bad "stop-verify: insecure state dir left junk or wrong exit (rc=$svbad_rc)"
fi
rm -rf "$sv_bad_tmp" "$sv_red"

# --- stop-verify malformed package.json -> BLOCK (fails closed, exit 2) with a
#     clear reason on stderr (FX2). A broken manifest must not silently disable
#     verification.
sv_mal="$(mktemp -d)"
printf 'this is not json {' > "$sv_mal/package.json"
svmal_out="$(printf '{"stop_hook_active":false,"session_id":"smoke-sv-malformed"}' \
    | CLAUDE_PROJECT_DIR="$sv_mal" bash "$HARNESS_KIT/hooks/stop-verify.sh" 2>&1)"
svmal_rc=$?
if [ "$svmal_rc" -eq 2 ] && printf '%s' "$svmal_out" | grep -q "package.json is malformed"; then
    ok "stop-verify: malformed package.json blocks (exit 2 + 'package.json is malformed')"
else
    bad "stop-verify: malformed package.json not blocked cleanly (rc=$svmal_rc)"
fi
rm -rf "$sv_mal"

# --- stop-verify non-object JSON `[]` on stdin -> coerced to {}, no crash (FX2).
#     Must be BOUNDED (exit 0 or 2) with no Python traceback on stderr.
sv_arr="$(mktemp -d)"
printf '{"scripts":{"test":"exit 1"}}\n' > "$sv_arr/package.json"
svarr_out="$(printf '[]' | CLAUDE_PROJECT_DIR="$sv_arr" bash "$HARNESS_KIT/hooks/stop-verify.sh" 2>&1)"
svarr_rc=$?
if { [ "$svarr_rc" -eq 0 ] || [ "$svarr_rc" -eq 2 ]; } \
   && ! printf '%s' "$svarr_out" | grep -q "Traceback"; then
    ok "stop-verify: non-object JSON [] on stdin does not crash (bounded exit, no traceback)"
else
    bad "stop-verify: [] on stdin crashed or was unbounded (rc=$svarr_rc)"
fi
rm -rf "$sv_arr"

# --- Test E: checklist gates at PreToolUse, records at PostToolUse (success-only) ---
py_hook="$HARNESS_KIT/hooks/pre-completion-checklist.py"
printf '{"name":"demo"}\n' > package.json   # marker so the gate engages

# PostToolUse fires ONLY on tool success (verified protocol fact), so record
# payloads carry no tool_response. The hook keys state on session_id + project
# root; we set CLAUDE_PROJECT_DIR="$WORK" so record and gate resolve to the same
# root deterministically (R3-3) without depending on the git-toplevel fallback.
# Codex ~L290: every checklist-hook invocation's EXIT STATUS is checked. The hook
# exits 0 on BOTH allow and deny, so a nonzero status means the python CRASHED —
# and a crash prints NO stdout, which a stdout-only "no deny -> allowed" check
# would silently misread as a PASS on an allow-expected assertion (a false green).
# record() asserts rc==0 inline (it runs in this shell); the gate helpers store rc
# in GATE_RC so each gate assertion can require GATE_RC -eq 0.
record() {   # session, command-string
    printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$WORK" "$2" \
        | CLAUDE_PROJECT_DIR="$WORK" python3 "$py_hook" >/dev/null 2>&1
    rec_rc=$?
    [ "$rec_rc" -eq 0 ] || bad "record: checklist hook crashed (rc=$rec_rc) for session $1"
}
run_gate_cmd() { # session, cwd, projdir, command -> sets GATE_OUT + GATE_RC
    GATE_OUT="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2" "$4" \
        | CLAUDE_PROJECT_DIR="$3" python3 "$py_hook")"
    GATE_RC=$?   # pipefail -> the python exit status, not printf's
}
run_gate() {    # session, cwd, projdir -> gate the default `git commit -m x`
    run_gate_cmd "$1" "$2" "$3" "git commit -m x"
}
run_gate_quoted() { # session, cwd, projdir, command -> sets GATE_OUT + GATE_RC
    # Like run_gate_cmd, but for a command containing EMBEDDED double quotes
    # (a spaced `-C "..."` path, a `-m "release; cd notes"` message). printf-based
    # JSON assembly (run_gate_cmd's approach) would corrupt on those quotes; build
    # the JSON with python's json.dumps via a heredoc (argv, not shell interpolation)
    # so the hook receives the literal command string, verified by construction.
    GATE_OUT="$(python3 - "$1" "$2" "$4" <<'PY' | CLAUDE_PROJECT_DIR="$3" python3 "$py_hook"
import json, sys
session, cwd, command = sys.argv[1:4]
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": session, "cwd": cwd, "tool_input": {"command": command}}))
PY
)"
    GATE_RC=$?   # pipefail -> the python exit status, not python-builder's
}

sess_unverified="smoke-$$-${RANDOM}-unverified"
run_gate "$sess_unverified" "$WORK" "$WORK"
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q '"permissionDecision": *"deny"'; then
    ok "E: unverified session -> PreToolUse deny"
else
    bad "E: expected a PreToolUse deny (rc=$GATE_RC)"
fi

sess_verified="smoke-$$-${RANDOM}-verified"
record "$sess_verified" "npm test"
record "$sess_verified" "npm run lint"
run_gate "$sess_verified" "$WORK" "$WORK"
if [ "$GATE_RC" -eq 0 ] && [ -z "$GATE_OUT" ]; then
    ok "E: verified session (PostToolUse-recorded) -> commit allowed"
else
    bad "E: expected allow after recording test + lint (rc=$GATE_RC)"
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
    run_gate "$neg_sess" "$WORK" "$WORK"
    if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q '"permissionDecision": *"deny"'; then
        ok "R1: non-anchored command not recorded, gate still denies: $bogus"
    else
        bad "R1: '$bogus' was wrongly accepted as a test verification (rc=$GATE_RC)"
    fi
done

# --- R4-1: project root is resolved from the EVENT cwd, not a stale CLAUDE_PROJECT_DIR ---
# Parameterized helpers so we can vary cwd and CLAUDE_PROJECT_DIR independently.
record_in() {  # session, cwd, projdir, command  (rc checked — Codex ~L290)
    printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2" "$4" \
        | CLAUDE_PROJECT_DIR="$3" python3 "$py_hook" >/dev/null 2>&1
    rec_rc=$?
    [ "$rec_rc" -eq 0 ] || bad "record_in: checklist hook crashed (rc=$rec_rc) for session $1"
}
# gate_in was folded into run_gate (session, cwd, projdir) above — it already
# takes an explicit cwd/projdir and stores GATE_OUT/GATE_RC so the exit status
# is asserted at every call site.

repo2="$(mktemp -d)"
( cd "$repo2" && git init -q && printf '{"name":"r2"}\n' > package.json )

# (a) A commit from a project SUBDIRECTORY is still gated (root resolves to the repo top).
mkdir -p "$WORK/subpkg"
sub_sess="smoke-$$-${RANDOM}-sub"
run_gate "$sub_sess" "$WORK/subpkg" "$WORK"
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q '"permissionDecision": *"deny"'; then
    ok "R4-1a: commit from a subdirectory is still gated"
else
    bad "R4-1a: a subdirectory commit was not gated (rc=$GATE_RC)"
fi

# (b) A verification run in repo2 must NOT authorize repo1, even though
#     CLAUDE_PROJECT_DIR still names repo1 (cwd wins).
xr_sess="smoke-$$-${RANDOM}-xrepo"
record_in "$xr_sess" "$repo2" "$WORK" "npm test"
record_in "$xr_sess" "$repo2" "$WORK" "npm run lint"
run_gate "$xr_sess" "$WORK" "$WORK"
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q '"permissionDecision": *"deny"'; then
    ok "R4-1b: a verification in a second repo does not authorize the first"
else
    bad "R4-1b: repo2 verification wrongly authorized repo1 (rc=$GATE_RC)"
fi

# (c) A verification in repo1 must NOT be consumed by a commit in repo2.
xr2_sess="smoke-$$-${RANDOM}-xrepo2"
record_in "$xr2_sess" "$WORK" "$WORK" "npm test"
record_in "$xr2_sess" "$WORK" "$WORK" "npm run lint"
run_gate "$xr2_sess" "$repo2" "$WORK"
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q '"permissionDecision": *"deny"'; then
    ok "R4-1c: a commit in the second repo does not consume the first repo's state"
else
    bad "R4-1c: repo1 state leaked into repo2 (rc=$GATE_RC)"
fi
rm -rf "$repo2" "$WORK/subpkg"

# --- R4-4: an insecure state dir -> the gate FAILS CLOSED (deny decision) ---
# Redirect the hook's temp base with TMPDIR and pre-plant the per-user state dir
# as a symlink; state_dir() must raise and the gate must emit a deny.
bad_tmp="$(mktemp -d)"
ln -s /tmp "$bad_tmp/claude-harness-$(id -u)"
r44_out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"smoke-r44","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$WORK" \
    | TMPDIR="$bad_tmp" CLAUDE_PROJECT_DIR="$WORK" python3 "$py_hook")"
r44_rc=$?   # Codex ~L290: a crash here must fail, not read as "no deny -> allow"
if [ "$r44_rc" -eq 0 ] && printf '%s' "$r44_out" | grep -q '"permissionDecision": *"deny"'; then
    ok "R4-4: insecure state dir -> gate denies (fail-closed)"
else
    bad "R4-4: gate should fail closed on an insecure state dir (rc=$r44_rc)"
fi
rm -rf "$bad_tmp"

# --- FX4: no-op-target anchoring. `make test-noop` shares the `make test` prefix
#     but the approved-command anchor `(?=\s|$)` rejects the `-noop` suffix, so it
#     records NO test evidence — with only a real lint on record the gate must DENY.
noop_sess="smoke-$$-${RANDOM}-noop"
record "$noop_sess" "make test-noop"   # must NOT count as a test (prefix only)
record "$noop_sess" "make lint"        # a real lint IS recorded
run_gate "$noop_sess" "$WORK" "$WORK"
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q '"permissionDecision": *"deny"'; then
    ok "FX4: 'make test-noop' is not recorded as a test; gate still denies"
else
    bad "FX4: 'make test-noop' was wrongly accepted as a test (rc=$GATE_RC)"
fi

# Positive control: the REAL targets do record and the gate approves.
pos_sess="smoke-$$-${RANDOM}-pos"
record "$pos_sess" "make test"
record "$pos_sess" "make lint"
run_gate "$pos_sess" "$WORK" "$WORK"
if [ "$GATE_RC" -eq 0 ] && [ -z "$GATE_OUT" ]; then
    ok "FX4: real 'make test' + 'make lint' -> gate approves"
else
    bad "FX4: expected allow after make test + make lint (rc=$GATE_RC)"
fi

# --- FX4: cross-repo retarget deny. Even with FRESH evidence for THIS repo, a
#     commit whose effective target is a DIFFERENT repo (a `git -C <other>` flag,
#     or a chained `cd <other> && git commit`) is denied BEFORE evidence is
#     consulted, with the standalone-commit reason.
retgt_sess="smoke-$$-${RANDOM}-retarget"
record "$retgt_sess" "make test"
record "$retgt_sess" "make lint"
run_gate_cmd "$retgt_sess" "$WORK" "$WORK" "git -C /other/repo commit -m x"
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q "standalone command from the repo root"; then
    ok "FX4: 'git -C <other> commit' denied with the standalone-commit reason"
else
    bad "FX4: 'git -C <other> commit' retarget not denied (rc=$GATE_RC)"
fi
run_gate_cmd "$retgt_sess" "$WORK" "$WORK" "cd /other && git commit -m x"
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q "standalone command from the repo root"; then
    ok "FX4: 'cd <other> && git commit' denied with the standalone-commit reason"
else
    bad "FX4: chained-cd retarget not denied (rc=$GATE_RC)"
fi

# --- FR3: shlex-based retarget detection on commands with EMBEDDED quotes,
#     which the old untokenized-regex gate mishandled in both directions.
#     Fresh recorded evidence per scenario; run_gate_quoted builds the event
#     JSON with python so the quotes reach the hook literally (printf-based
#     JSON would corrupt on them). ---
qc_sess="smoke-$$-${RANDOM}-quoted-C"
record "$qc_sess" "make test"
record "$qc_sess" "make lint"
run_gate_quoted "$qc_sess" "$WORK" "$WORK" 'git -C "/other repo" commit -m x'
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q "standalone command from the repo root"; then
    ok "FR3: quoted 'git -C \"<spaced path>\" commit' denied with the standalone-commit reason"
else
    bad "FR3: quoted -C retarget not denied (rc=$GATE_RC)"
fi

qsub_sess="smoke-$$-${RANDOM}-subshell-cd"
record "$qsub_sess" "make test"
record "$qsub_sess" "make lint"
run_gate_quoted "$qsub_sess" "$WORK" "$WORK" '(cd /other && git commit -m x)'
# Accepted NUDGE limitation (right-sized gate): a `cd` retarget INSIDE a subshell
# tokenizes to `(cd` — not a bare `cd` token — so the simple token check does not
# flag it. This is an INTENTIONAL miss; the git-level pre-commit-verify.sh hook is
# the enforcing boundary. See the module comment in pre-completion-checklist.py.
if [ "$GATE_RC" -eq 0 ] && [ -z "$GATE_OUT" ]; then
    ok "FR3: subshell '(cd ... && git commit)' is an accepted nudge miss (allowed; git hook enforces)"
else
    bad "FR3: subshell-cd unexpectedly gated (rc=$GATE_RC, out=$GATE_OUT)"
fi

qmsg_sess="smoke-$$-${RANDOM}-cd-in-message"
record "$qmsg_sess" "make test"
record "$qmsg_sess" "make lint"
run_gate_quoted "$qmsg_sess" "$WORK" "$WORK" 'git commit -m "release; cd notes"'
if [ "$GATE_RC" -eq 0 ] && [ -z "$GATE_OUT" ]; then
    ok "FR3: operators inside a quoted commit message do not trigger a false-positive deny"
else
    bad "FR3: 'cd notes' inside a quoted message was wrongly denied (rc=$GATE_RC, out=$GATE_OUT)"
fi

# --- Right-sized gate regression (a4e8a4e): the raw-text regex still catches
#     wrapper-prefixed commit invocations (missing-evidence deny, no evidence
#     recorded for either session), while a `commit` appearing only as a FLAG
#     VALUE (not the subcommand) is not over-detected as a commit at all. ---
wrap_env_sess="smoke-$$-${RANDOM}-wrap-env"
run_gate_cmd "$wrap_env_sess" "$WORK" "$WORK" "env git commit -m x"
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q "PRE-COMPLETION CHECKLIST"; then
    ok "regression: 'env git commit -m x' wrapper prefix detected as a commit (missing-evidence deny)"
else
    bad "regression: 'env git commit -m x' not detected as a commit (rc=$GATE_RC)"
fi

wrap_bashc_sess="smoke-$$-${RANDOM}-wrap-bashc"
run_gate_quoted "$wrap_bashc_sess" "$WORK" "$WORK" 'bash -c "git commit"'
if [ "$GATE_RC" -eq 0 ] && printf '%s' "$GATE_OUT" | grep -q "PRE-COMPLETION CHECKLIST"; then
    ok 'regression: bash -c "git commit" wrapper detected as a commit (missing-evidence deny)'
else
    bad "regression: bash -c \"git commit\" not detected as a commit (rc=$GATE_RC)"
fi

grep_commit_sess="smoke-$$-${RANDOM}-grep-commit"
run_gate_cmd "$grep_commit_sess" "$WORK" "$WORK" "git log --grep=commit"
if [ "$GATE_RC" -eq 0 ] && [ -z "$GATE_OUT" ]; then
    ok "regression: 'git log --grep=commit' is not over-detected as a commit (gate silent)"
else
    bad "regression: 'git log --grep=commit' wrongly gated (rc=$GATE_RC, out=$GATE_OUT)"
fi

# --- Position-aware git parse (Codex re-gate-3): the three former false-DENYs.
#     Retarget/subcommand detection now respects git's structure
#     (`git [GLOBAL-OPTS] <subcommand> [SUBCOMMAND-ARGS]`), so a `-C` that is
#     `commit`'s OWN reuse option, a `cd` that is only a `-m` message value, and a
#     `commit` that is only a `--grep` flag value are no longer misread. ---
# (1) `git commit -C HEAD`: -C is AFTER the subcommand -> commit's own reuse
#     option, not a global retarget. With fresh evidence the gate must APPROVE.
cflag_sess="smoke-$$-${RANDOM}-commit-Cflag"
record "$cflag_sess" "make test"
record "$cflag_sess" "make lint"
run_gate_cmd "$cflag_sess" "$WORK" "$WORK" "git commit -C HEAD"
if [ "$GATE_RC" -eq 0 ] && [ -z "$GATE_OUT" ]; then
    ok "regression: 'git commit -C HEAD' (commit's own -C) is not a false retarget deny"
else
    bad "regression: 'git commit -C HEAD' wrongly gated (rc=$GATE_RC, out=$GATE_OUT)"
fi

# (2) `git commit -m cd`: the `cd` is a `-m` message VALUE, not a chained command
#     word, so it is not a false retarget. With fresh evidence the gate APPROVES.
cdmsg_sess="smoke-$$-${RANDOM}-commit-cd-msg"
record "$cdmsg_sess" "make test"
record "$cdmsg_sess" "make lint"
run_gate_cmd "$cdmsg_sess" "$WORK" "$WORK" "git commit -m cd"
if [ "$GATE_RC" -eq 0 ] && [ -z "$GATE_OUT" ]; then
    ok "regression: 'git commit -m cd' (cd as a message value) is not a false retarget deny"
else
    bad "regression: 'git commit -m cd' wrongly gated (rc=$GATE_RC, out=$GATE_OUT)"
fi

# (3) `git log --grep commit` (space form): the `commit` token is the VALUE of
#     --grep, not the subcommand, so the gate stays SILENT (not a commit).
grepsp_sess="smoke-$$-${RANDOM}-grep-commit-space"
run_gate_cmd "$grepsp_sess" "$WORK" "$WORK" "git log --grep commit"
if [ "$GATE_RC" -eq 0 ] && [ -z "$GATE_OUT" ]; then
    ok "regression: 'git log --grep commit' (space form) is not over-detected as a commit (gate silent)"
else
    bad "regression: 'git log --grep commit' wrongly gated (rc=$GATE_RC, out=$GATE_OUT)"
fi

# --- FX4: malformed gate event. A PreToolUse Bash event with `tool_input: null`
#     (identifiably a commit-gate evaluation but unparseable) must emit an EXPLICIT
#     deny (fail-closed) and never raise a traceback.
malgate_out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"smoke-malformed-gate","cwd":"%s","tool_input":null}' "$WORK" \
    | CLAUDE_PROJECT_DIR="$WORK" python3 "$py_hook" 2>&1)"
malgate_rc=$?
if [ "$malgate_rc" -eq 0 ] && printf '%s' "$malgate_out" | grep -q '"permissionDecision": *"deny"' \
   && ! printf '%s' "$malgate_out" | grep -q "Traceback"; then
    ok "FX4: malformed gate event (tool_input null) -> explicit deny, no traceback"
else
    bad "FX4: malformed gate event not denied cleanly (rc=$malgate_rc)"
fi

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

# --- Containment (c) / FX5: a symlink-ESCAPE destination is REFUSED (fatal). A
#     `.claude` symlink pointing OUTSIDE the repo would place harness files beyond
#     the project root; assert_contained resolves the realpath BEFORE any mkdir,
#     so the install exits nonzero with the containment message and writes ZERO
#     files into the external target. Force direct mode so it is valid under either
#     outer mode.
se_repo="$(mktemp -d)"
se_ext="$(mktemp -d)"          # external target OUTSIDE se_repo
(
    cd "$se_repo" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    ln -s "$se_ext" .claude    # a symlinked ancestor that escapes the repo
)
se_out="$(cd "$se_repo" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" 2>&1)"
se_rc=$?
se_snap="$(snapshot "$se_ext")"
if [ "$se_rc" -ne 0 ] && printf '%s' "$se_out" | grep -q "resolves outside the project root" \
   && [ -z "$se_snap" ]; then
    ok "FX5: symlink-escape .claude refused (fatal); external target left empty"
else
    bad "FX5: symlink-escape not refused or external target written (rc=$se_rc)"
fi
rm -rf "$se_repo" "$se_ext"

# --- Containment (d) / FR1: a symlinked LEAF destination is REFUSED (fatal),
#     even when it is DANGLING. `docs/` is a real dir here (so assert_contained
#     docs passes), but docs/golden-principles.md is a symlink to a path OUTSIDE
#     the repo whose target does not exist — `[ -f ]` is false for a dangling
#     symlink, so the old code fell into the "create" branch and wrote THROUGH
#     it to the external target. refuse_symlink_leaf's `-L` test catches a
#     symlink regardless of whether its target exists, so the install must now
#     abort before ever writing. Force direct mode so it is valid under either
#     outer mode.
dl_repo="$(mktemp -d)"
dl_ext="$(mktemp -d)"          # external target dir OUTSIDE dl_repo; symlink points here
(
    cd "$dl_repo" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    mkdir -p docs
    ln -s "$dl_ext/golden-principles.md" docs/golden-principles.md   # dangling: target absent
)
dl_out="$(cd "$dl_repo" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" 2>&1)"
dl_rc=$?
dl_snap="$(snapshot "$dl_ext")"
if [ "$dl_rc" -ne 0 ] && printf '%s' "$dl_out" | grep -q "is a symlink. Refusing to write through it" \
   && [ -z "$dl_snap" ]; then
    ok "FR1: dangling docs/golden-principles.md symlink refused; external target left empty"
else
    bad "FR1: docs-leaf symlink escape not refused or external target written (rc=$dl_rc)"
fi
rm -rf "$dl_repo" "$dl_ext"

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

# --- Transactional rollback (QA gap: the mid-transaction _restore_hook path was
#     never driven). Mechanism: plant a marker-owned but READ-ONLY (0400)
#     post-commit. Its snapshot (cp -p) can READ it, and preflight passes, so the
#     transaction proceeds and pre-commit is applied FIRST — then _apply_raw_hook
#     post-commit tries to re-materialize the differing body by writing the 0400
#     (non-writable) file, which FAILS. That post-apply failure drives
#     `_restore_hook` for BOTH hooks. Assert: install exits nonzero, the rollback
#     banner is printed, and pre-commit is restored to its pre-install state
#     (ABSENT — `git init` creates no active pre-commit). Force direct mode.
rb="$(mktemp -d)"
(
    cd "$rb" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    printf '{"name":"demo"}\n' > package.json
    git add -A && git commit -q --no-verify -m init
    printf '#!/usr/bin/env bash\n# harness-kit hook\n' > .git/hooks/post-commit
    chmod 0400 .git/hooks/post-commit
)
rb_out="$(cd "$rb" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" 2>&1)"
rb_rc=$?
if [ "$rb_rc" -ne 0 ] && printf '%s' "$rb_out" | grep -q "rolling back BOTH hooks" \
   && [ ! -e "$rb/.git/hooks/pre-commit" ]; then
    ok "rollback: post-commit apply failure rolls back BOTH hooks; pre-commit restored to absent"
else
    bad "rollback: expected nonzero exit + rollback banner + pre-commit absent (rc=$rb_rc)"
fi
rm -rf "$rb"

# --- FX5: a marker-OWNED but body-less (marker-only) post-commit is NOT trusted by
#     its body — it is re-materialized byte-for-byte with the real hook body (not
#     merely chmod'd), so the cleanup wiring is restored. Direct mode.
mo="$(mktemp -d)"
(
    cd "$mo" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    printf '{"name":"demo"}\n' > package.json
    git add -A && git commit -q --no-verify -m init
    printf '#!/usr/bin/env bash\n# harness-kit hook\n' > .git/hooks/post-commit
    chmod +x .git/hooks/post-commit
)
( cd "$mo" && HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" ) >/dev/null 2>&1
mo_rc=$?
if [ "$mo_rc" -eq 0 ] \
   && grep -Fq '.harness/hooks/post-commit-cleanup.sh' "$mo/.git/hooks/post-commit" \
   && [ -x "$mo/.git/hooks/post-commit" ]; then
    ok "FX5: marker-only post-commit re-materialized with the cleanup body + executable"
else
    bad "FX5: marker-only post-commit not re-materialized (rc=$mo_rc)"
fi
rm -rf "$mo"

# --- FX5: a .gitignore whose last line lacks a trailing newline must not have the
#     harness entry merged onto the user's final pattern. Direct mode.
gi="$(mktemp -d)"
(
    cd "$gi" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    printf '{"name":"demo"}\n' > package.json
    printf 'node_modules/' > .gitignore    # NO trailing newline
    HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" >/dev/null 2>&1
)
if grep -Fxq 'node_modules/' "$gi/.gitignore" && grep -Fxq '.harness-verified' "$gi/.gitignore"; then
    ok "FX5: .gitignore without a trailing newline keeps .harness-verified on its own line"
else
    bad "FX5: .harness-verified was merged onto the prior .gitignore pattern"
fi
rm -rf "$gi"

# --- Stamp deletion (QA gap: assert the post-commit cleanup actually DELETES the
#     stamp, not merely that the commit succeeded). Fresh sub-repo, forced direct
#     mode, full install + stamped project commit; the raw post-commit hook must
#     remove .harness-verified end-to-end (complements Test C, which runs under the
#     ambient outer mode in the main repo).
sd="$(mktemp -d)"
(
    cd "$sd" || exit 1
    git init -q && git config user.email a@b.c && git config user.name t
    printf '{"name":"demo"}\n' > package.json
    HARNESS_KIT_HOOK_MODE=direct bash "$HARNESS_KIT/install.sh" >/dev/null 2>&1
    git add -A && git commit -q --no-verify -m init
    printf 'console.log(1);\n' > app.js
    git add app.js
    touch .harness-verified
)
sd_rc=0
( cd "$sd" && git commit -q -m "feat: stamped change" ) >/dev/null 2>&1 || sd_rc=$?
if [ "$sd_rc" -eq 0 ] && [ ! -e "$sd/.harness-verified" ]; then
    ok "stamp-deletion: post-commit cleanup deletes .harness-verified after a stamped commit"
else
    bad "stamp-deletion: stamp not deleted after a stamped commit (rc=$sd_rc)"
fi
rm -rf "$sd"

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
