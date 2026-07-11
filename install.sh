#!/usr/bin/env bash
# Install the universal harness into a project.
#
# Usage:
#   cd /path/to/your/project
#   ~/src/harness-kit/install.sh
#
# What it does:
#   1. Copies AGENTS.md (if not present) or warns if one exists
#   2. Copies docs/golden-principles.md
#   3. Sets up git hooks (.harness/hooks/ + .pre-commit-config.yaml)
#   4. Adds .harness-verified to .gitignore
#   5. Creates thin CLAUDE.md wrapper (if not present)
#   6. Creates thin .cursor/rules/harness.md wrapper (if not present)

set -euo pipefail

HARNESS_KIT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(pwd)"

echo "Installing harness into: $PROJECT_ROOT"
echo ""

# Require running from the git top-level (works with worktrees, where .git is a file).
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$TOPLEVEL" ]; then
    echo "ERROR: Not a git repository. Run from a project root."
    exit 1
fi
if [ ! "$TOPLEVEL" -ef "$PROJECT_ROOT" ]; then
    echo "ERROR: Run install.sh from the repository root: $TOPLEVEL"
    exit 1
fi

# Internal/testing seam (R2-R5): force the hook-install path deterministically.
#   direct    = raw git hooks even if the pre-commit framework is installed
#   precommit = require the pre-commit framework (error if missing)
#   auto      = auto-detect (default, current behavior)
HOOK_MODE="${HARNESS_KIT_HOOK_MODE:-auto}"
case "$HOOK_MODE" in
    auto|direct|precommit) : ;;
    *)
        echo "ERROR: HARNESS_KIT_HOOK_MODE must be auto, direct, or precommit (got: $HOOK_MODE)"
        exit 1 ;;
esac
HOOKS_ACTIVE=false        # flipped true only once hooks are actually wired (R6 banner)
INACTIVE_REASON="foreign" # why hooks are inactive: foreign|refused|worktree (drives the banner)

# R5-1: detect a LINKED git worktree. A linked worktree shares its hooks directory
# with the primary worktree via git-common-dir, but the harness wrappers invoke
# worktree-local paths (.harness/hooks/*). Writing those shared hooks from here would
# break commits from the primary worktree, from sibling worktrees, and after this
# worktree is removed. Both the raw-hook and pre-commit-framework paths write to that
# same shared dir, so hook wiring is refused for a linked worktree regardless of mode.
# Detection: a linked worktree's --absolute-git-dir (.git/worktrees/<name>) differs
# from its --git-common-dir (.git). Canonicalize both before comparing, because
# --git-common-dir is often returned RELATIVE (".git") from the primary top-level and
# would otherwise look different from the absolute git dir (false positive).
WORKTREE_LINKED=false
_gd_raw="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
_gc_raw="$(git rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "$_gd_raw" ] && [ -n "$_gc_raw" ]; then
    _gd="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$_gd_raw")"
    _gc="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$_gc_raw")"
    [ "$_gd" != "$_gc" ] && WORKTREE_LINKED=true
fi

# 1. AGENTS.md
if [ -f AGENTS.md ]; then
    echo "⟳ AGENTS.md already exists — skipping (review manually)"
else
    cp "$HARNESS_KIT/AGENTS.md" AGENTS.md
    echo "✓ Created AGENTS.md (edit the placeholder sections)"
fi

# 2. Golden Principles
mkdir -p docs
if [ -f docs/golden-principles.md ]; then
    echo "⟳ docs/golden-principles.md already exists — skipping"
else
    cp "$HARNESS_KIT/docs/golden-principles.md" docs/golden-principles.md
    echo "✓ Created docs/golden-principles.md"
fi

# 2b. Human-reference + code-style docs (README's "What It Creates" lists these)
for doc in harness-philosophy.md code-style.md; do
    if [ -f "docs/$doc" ]; then
        echo "⟳ docs/$doc already exists — skipping"
    else
        cp "$HARNESS_KIT/docs/$doc" "docs/$doc"
        echo "✓ Created docs/$doc"
    fi
done

# 3. Git hooks
mkdir -p .harness/hooks
for hook in no-mocks.sh pre-commit-verify.sh post-commit-cleanup.sh; do
    if [ -f ".harness/hooks/$hook" ]; then
        echo "⟳ .harness/hooks/$hook already exists — skipping (delete it to re-install a fresh copy)"
    else
        cp "$HARNESS_KIT/hooks/$hook" ".harness/hooks/$hook"
        chmod +x ".harness/hooks/$hook"
        echo "✓ Created .harness/hooks/$hook"
    fi
done

# 4. Pre-commit config
# R4-3 (conservative): treat ANY pre-existing config that is not BYTE-IDENTICAL to
# the harness's own as foreign. A string-grep for our three hook paths would pass a
# partial merge (right paths, wrong stage), a commented-out entry, or a disabled
# hook — all of which leave the harness checks inactive. Byte-identity is simple and
# has no false "active"; a user who intentionally merged our hooks into their own
# config keeps it (we do not overwrite) and just wires it up manually.
CONFIG_FOREIGN=false
if [ -f .pre-commit-config.yaml ]; then
    if cmp -s .pre-commit-config.yaml "$HARNESS_KIT/.pre-commit-config.yaml"; then
        echo "⟳ .pre-commit-config.yaml is the harness config (byte-identical) — skipping"
    else
        CONFIG_FOREIGN=true
        echo "⚠ .pre-commit-config.yaml exists and differs from the harness config (treated as foreign)"
    fi
else
    cp "$HARNESS_KIT/.pre-commit-config.yaml" .pre-commit-config.yaml
    echo "✓ Created .pre-commit-config.yaml"
fi

# install_raw_git_hooks: wire raw git hooks, chaining any existing (foreign) hook.
# Sets HOOKS_ACTIVE=true on success. Honors core.hooksPath but REFUSES to write
# outside the repo (R3).
_realpath() { python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

# preflight_raw_hook: validate a target hook WITHOUT mutating anything (R3-2).
# Refuses a symlink target or a preserved-name collision. Returns non-zero to
# refuse. Called for BOTH hooks before either is written, so we never leave a
# half-installed state.
preflight_raw_hook() {
    local name="$1"
    local target="$HOOKS_DIR/$name"
    local preserved="$target.harness-preserved"
    if [ -L "$target" ]; then
        echo "ERROR: $target is a symlink. Refusing to overwrite it."
        echo "       Remove or resolve it manually, then re-run install.sh."
        return 1
    fi
    # -Fxq: the marker must be a WHOLE line exactly `# harness-kit hook`, not a
    # substring that could appear inside an unrelated foreign hook's comment.
    if [ -e "$target" ] && ! grep -Fxq '# harness-kit hook' "$target" 2>/dev/null \
       && [ -e "$preserved" ]; then
        echo "ERROR: $target is not a harness hook and $preserved already exists."
        echo "       Refusing to overwrite. Resolve manually, then re-run."
        return 1
    fi
    return 0
}

# --- Transactional two-hook install (R5-2) ---------------------------------
# pre-commit and post-commit are installed as ONE transaction: both targets (and
# their .harness-preserved siblings) are snapshotted before any mutation, and if
# EITHER hook fails to apply, BOTH are restored to their exact pre-install state.
# This closes the partial-install window where pre-commit is written and active
# but post-commit fails, leaving hooks half-wired while the banner says inactive.

# _snap_one: back up one path (content+mode) into the txn dir, recording existence.
_snap_one() {
    local src="$1" dst="$2"
    if [ -e "$src" ] || [ -L "$src" ]; then
        cp -p "$src" "$dst" || return 1          # -p preserves mode+timestamps (POSIX)
        : > "$dst.exists"
    fi
    return 0
}

# _snapshot_hook: snapshot both the hook target and its preserved sibling.
_snapshot_hook() {
    local name="$1" txn="$2"
    local target="$HOOKS_DIR/$name"
    _snap_one "$target"                 "$txn/$name.target"    || return 1
    _snap_one "$target.harness-preserved" "$txn/$name.preserved" || return 1
    return 0
}

# _restore_one: restore one path to its snapshot; remove it if it was absent.
# Rollback ops are CHECKED and failures reported loudly (a silent rollback failure
# would leave the repo in the very half-state the transaction exists to prevent).
_restore_one() {
    local dst="$1" snap="$2"
    if [ -e "$snap.exists" ]; then
        cp -p "$snap" "$dst" || { echo "ERROR: rollback failed to restore $dst" >&2; return 1; }
    elif [ -e "$dst" ] || [ -L "$dst" ]; then
        rm -f "$dst" || { echo "ERROR: rollback failed to remove $dst" >&2; return 1; }
    fi
    return 0
}

# _restore_hook: restore both the target and the preserved sibling for one hook.
_restore_hook() {
    local name="$1" txn="$2"
    local target="$HOOKS_DIR/$name"
    _restore_one "$target"                 "$txn/$name.target"
    _restore_one "$target.harness-preserved" "$txn/$name.preserved"
}

# _apply_raw_hook: mutate ONE hook (snapshot + preflight must have passed). Chains a
# foreign hook by renaming it to <hook>.harness-preserved, writes our marked wrapper,
# and chmods it. A marker-owned but NON-executable hook (a prior half-install) is
# repaired with chmod INSIDE the transaction, so it is rolled back cleanly if the
# OTHER hook later fails. Every mutating step is checked (this runs left of `||`,
# where `set -e` is suspended). Returns non-zero on any failure; the caller rolls back.
_apply_raw_hook() {
    local name="$1" body="$2"
    local target="$HOOKS_DIR/$name"
    local preserved="$target.harness-preserved"
    if grep -Fxq '# harness-kit hook' "$target" 2>/dev/null; then
        # Already our wrapper (idempotent re-run) — ensure it is executable (R5-2).
        chmod +x "$target" || return 1
        return 0
    fi
    if [ -e "$target" ]; then
        mv "$target" "$preserved" || return 1
        echo "⚠ Preserved existing $name as $name.harness-preserved (chained, not disabled)"
    fi
    if ! printf '%s\n' "$body" > "$target" || ! chmod +x "$target"; then
        return 1
    fi
    echo "✓ Installed $name git hook"
    return 0
}

# install_raw_git_hooks: wire raw git hooks, chaining any existing (foreign) hook.
# Sets HOOKS_ACTIVE=true on success. Honors core.hooksPath but REFUSES (without
# mutating anything) to write outside the repo (R3-2).
install_raw_git_hooks() {
    local hooks_dir abs toplevel gitdir commondir
    hooks_dir="$(git rev-parse --git-path hooks)"       # honors core.hooksPath
    # Resolve to a canonical absolute path BEFORE creating anything (R3-2 — a
    # refused external path must not be created as a side effect). realpath does
    # not require the path to exist, so no mkdir is needed to resolve it.
    abs="$(_realpath "$hooks_dir")"
    toplevel="$(_realpath "$(git rev-parse --show-toplevel)")"
    gitdir="$(_realpath "$(git rev-parse --absolute-git-dir)")"
    commondir="$(_realpath "$(git rev-parse --git-common-dir)")"
    # Allow containment under the worktree top-level OR the git dir OR the common
    # dir. Linked worktrees put shared hooks under the common dir (verified), so
    # omitting it would refuse the legitimate default path.
    case "$abs/" in
        "$toplevel"/*|"$gitdir"/*|"$commondir"/*) : ;;   # inside the repo — OK
        *)
            echo "ERROR: git hooks dir resolves outside the repo: $abs"
            echo "       (core.hooksPath points to an external location). Refusing."
            INACTIVE_REASON="refused"
            return 1 ;;
    esac
    HOOKS_DIR="$abs"

    # Preflight BOTH targets before touching either — all-or-nothing.
    if ! preflight_raw_hook pre-commit || ! preflight_raw_hook post-commit; then
        INACTIVE_REASON="refused"
        return 1
    fi
    mkdir -p "$HOOKS_DIR" || { INACTIVE_REASON="refused"; return 1; }

    # Bodies are single-quoted so $0/$@/$? stay literal in the written hook file.
    local pre_body post_body
    # shellcheck disable=SC2016  # $-refs are intentionally literal in the hook body
    pre_body='#!/usr/bin/env bash
# harness-kit hook
# Harness pre-commit: chain any preserved hook, then run harness checks.
set -euo pipefail
HOOK_DIR="$(dirname "$0")"
if [ -x "$HOOK_DIR/pre-commit.harness-preserved" ]; then
    "$HOOK_DIR/pre-commit.harness-preserved" "$@" || exit $?
fi
.harness/hooks/no-mocks.sh && .harness/hooks/pre-commit-verify.sh'

    # shellcheck disable=SC2016  # $-refs are intentionally literal in the hook body
    post_body='#!/usr/bin/env bash
# harness-kit hook
# Harness post-commit: chain any preserved hook, then clean up the stamp.
HOOK_DIR="$(dirname "$0")"
if [ -x "$HOOK_DIR/post-commit.harness-preserved" ]; then
    "$HOOK_DIR/post-commit.harness-preserved" "$@" || true
fi
.harness/hooks/post-commit-cleanup.sh'

    # Transaction (R5-2): snapshot BOTH hooks, apply both, and on ANY failure
    # restore BOTH so we never leave pre-commit active while post-commit failed.
    local txn
    txn="$(mktemp -d "${TMPDIR:-/tmp}/harness-hooktxn.XXXXXX")" \
        || { INACTIVE_REASON="refused"; return 1; }
    if ! _snapshot_hook pre-commit "$txn" || ! _snapshot_hook post-commit "$txn"; then
        rm -rf "$txn"; INACTIVE_REASON="refused"; return 1
    fi
    if ! _apply_raw_hook pre-commit "$pre_body" \
       || ! _apply_raw_hook post-commit "$post_body"; then
        echo "ERROR: hook install failed — rolling back BOTH hooks to their prior state." >&2
        _restore_hook pre-commit "$txn"
        _restore_hook post-commit "$txn"
        rm -rf "$txn"; INACTIVE_REASON="refused"; return 1
    fi
    rm -rf "$txn"
    HOOKS_ACTIVE=true
}

# install_precommit_framework: wire hooks via the pre-commit framework.
# Sets HOOKS_ACTIVE=true on success; returns 1 if pre-commit is missing OR if
# either install step fails (R3-1 — a failed install must not report success).
install_precommit_framework() {
    if ! command -v pre-commit &> /dev/null; then
        return 1
    fi
    pre-commit install || return 1
    pre-commit install --hook-type post-commit || return 1
    echo "✓ Installed pre-commit hooks"
    HOOKS_ACTIVE=true
}

# Decide the hook-install path. A foreign/partial .pre-commit-config.yaml blocks
# BOTH auto and precommit (installing the framework would run the user's config,
# not ours); direct mode ignores the config entirely because it writes raw hooks.
if [ "$WORKTREE_LINKED" = true ]; then
    # R5-1: refuse hook wiring from a LINKED worktree, for ALL modes and BOTH the
    # raw-hook and framework paths (they write to the same shared common-dir hooks).
    # Nothing is written to the shared hooks dir; the banner reports NOT active.
    INACTIVE_REASON="worktree"
    echo "⚠ WARNING: harness hooks are NOT active."
    echo "  install.sh was run from a LINKED git worktree. Its hooks are shared with"
    echo "  the primary worktree but would depend on THIS worktree's local files, so"
    echo "  installing them here would break commits in the primary and sibling"
    echo "  worktrees. Re-run install.sh from the PRIMARY worktree to wire hooks."
elif [ "$CONFIG_FOREIGN" = true ] && [ "$HOOK_MODE" = precommit ]; then
    echo "ERROR: HARNESS_KIT_HOOK_MODE=precommit but .pre-commit-config.yaml is a"
    echo "       foreign/partial config. Merge the harness hooks first, then re-run."
    exit 1
elif [ "$CONFIG_FOREIGN" = true ] && [ "$HOOK_MODE" = auto ]; then
    # Do NOT install over a foreign config and do NOT claim success — harness
    # hooks stay inactive (HOOKS_ACTIVE=false) until the user merges.
    INACTIVE_REASON="foreign"
    echo "⚠ WARNING: harness hooks are NOT active."
    echo "  Your existing .pre-commit-config.yaml was left untouched. Merge the"
    echo "  harness hooks from $HARNESS_KIT/.pre-commit-config.yaml into it, then run:"
    echo "     pre-commit install && pre-commit install --hook-type post-commit"
    echo "  Until merged, no-mocks and verify checks will NOT run."
elif [ "$HOOK_MODE" = precommit ]; then
    if ! install_precommit_framework; then
        echo "ERROR: HARNESS_KIT_HOOK_MODE=precommit but the pre-commit framework"
        echo "       is not installed. Install it (pipx install pre-commit) and re-run."
        exit 1
    fi
elif [ "$HOOK_MODE" = direct ]; then
    echo "Installing raw git hooks (HARNESS_KIT_HOOK_MODE=direct)"
    install_raw_git_hooks || exit 1   # explicit direct mode: a refusal is fatal (R3-2)
elif install_precommit_framework; then
    :   # auto: framework present and used
else
    echo "pre-commit not found — installing raw git hooks"
    install_raw_git_hooks || true     # auto fallback: a refusal leaves hooks inactive
fi

# 5. Gitignore additions
IGNORE_ENTRIES=(".harness-verified")
for entry in "${IGNORE_ENTRIES[@]}"; do
    if ! grep -qF "$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
        echo "✓ Added $entry to .gitignore"
    fi
done

# 6. Thin CLAUDE.md wrapper (Claude Code)
if [ ! -f CLAUDE.md ]; then
    cat > CLAUDE.md << 'EOF'
# CLAUDE.md

Read AGENTS.md for project conventions, boundaries, and commands.
Read docs/golden-principles.md when: making architectural decisions or resolving ambiguity.

## Claude-Specific
- Use subagent-driven development for implementation plans
- Capture significant architectural decisions as decision records (see docs/decision-record-template.md)
- If you use a code-navigation MCP server, prefer it over reading whole files
EOF
    echo "✓ Created CLAUDE.md (thin wrapper pointing to AGENTS.md)"
fi

# 7. Thin Cursor rules wrapper
mkdir -p .cursor/rules
if [ -f .cursor/rules/harness.md ]; then
    echo "⟳ .cursor/rules/harness.md already exists — skipping"
else
    cat > .cursor/rules/harness.md << 'EOF'
# Harness Rules

Read AGENTS.md for project conventions, boundaries, and commands.
Read docs/golden-principles.md for architectural decision-making principles.

Key rules:
- NEVER use mocks in tests (see AGENTS.md → Testing)
- NEVER commit without running tests and lint first
- NEVER retry a failed approach more than 3 times — escalate
EOF
    echo "✓ Created .cursor/rules/harness.md (thin wrapper)"
fi

# 8. Reference-doc templates (progressive-disclosure sources)
for doc in decision-record-template.md eval-template.md escape-hatch-audit.md context-inheritance-audit.md; do
    if [ -f "docs/$doc" ]; then
        echo "⟳ docs/$doc already exists — skipping"
    else
        cp "$HARNESS_KIT/docs/$doc" "docs/$doc"
        echo "✓ Created docs/$doc"
    fi
done

# 9. Structural review skill (portable copy for any agent)
mkdir -p skills
if [ -f skills/review.md ]; then
    echo "⟳ skills/review.md already exists — skipping"
else
    cp "$HARNESS_KIT/skills/review.md" skills/review.md
    echo "✓ Created skills/review.md"
fi

# 9b. Claude Code skill form: frontmatter + the verbatim review skill body
mkdir -p .claude/skills/review
if [ -f .claude/skills/review/SKILL.md ]; then
    echo "⟳ .claude/skills/review/SKILL.md already exists — skipping"
else
    {
        printf -- '---\n'
        printf 'name: review\n'
        printf 'description: Structural code audit — find bugs (not improvements) with severity and location.\n'
        printf -- '---\n\n'
        cat "$HARNESS_KIT/skills/review.md"
    } > .claude/skills/review/SKILL.md
    echo "✓ Created .claude/skills/review/SKILL.md"
fi

# 10. Claude Code dynamic hooks (inert until wired into .claude/settings.json)
mkdir -p .claude/hooks
for hook in stop-verify.sh pre-completion-checklist.py settings-snippet.json; do
    if [ -f ".claude/hooks/$hook" ]; then
        echo "⟳ .claude/hooks/$hook already exists — skipping"
    else
        cp "$HARNESS_KIT/hooks/$hook" ".claude/hooks/$hook"
        echo "✓ Created .claude/hooks/$hook"
    fi
done
chmod +x .claude/hooks/stop-verify.sh
echo "✓ Claude Code hooks present in .claude/hooks/ (wire up manually — see next steps)"

echo ""
echo "========================================="
if [ "$HOOKS_ACTIVE" = true ]; then
    echo "Harness installed successfully. Git hooks are active."
    echo "========================================="
else
    echo "Files installed — but git hooks are NOT active."
    echo "========================================="
    if [ "$INACTIVE_REASON" = worktree ]; then
        echo "install.sh was run from a LINKED git worktree. Re-run it from the PRIMARY"
        echo "worktree to wire hooks — hooks are shared across worktrees but depend on"
        echo "worktree-local files, so they are not installed from a linked worktree."
    elif [ "$INACTIVE_REASON" = refused ]; then
        echo "Raw git hooks could not be installed (the hooks path is outside the"
        echo "repo, a hook target is a symlink, or a write failed). Wire the harness"
        echo "hooks from your configured hooks path manually — see docs/. no-mocks"
        echo "and verify will NOT run until then."
    else
        echo "Merge the harness entries from .pre-commit-config.yaml (see the warning"
        echo "above), then run: pre-commit install && pre-commit install --hook-type post-commit"
        echo "Until merged, no-mocks and verify checks will NOT run."
    fi
fi
echo ""
echo "Next steps:"
echo "  1. Edit AGENTS.md — fill in the placeholder sections"
echo "  2. Commit: git add AGENTS.md CLAUDE.md docs/ .harness/ .pre-commit-config.yaml"
echo "  3. Test: touch .harness-verified && git commit -m 'test: harness install'"
echo ""
echo "Claude Code users — enable the dynamic hooks:"
echo "  Merge .claude/hooks/settings-snippet.json into .claude/settings.json"
echo "  (Stop: verify before finishing; PreToolUse: commit gate; PostToolUse: record verification)"
echo ""
echo "The verification stamp workflow:"
echo "  npm test && npm run lint && touch .harness-verified"
echo "  git commit -m 'feat: your change'"
echo "  (stamp auto-deleted after commit, must re-verify next time)"
echo ""
