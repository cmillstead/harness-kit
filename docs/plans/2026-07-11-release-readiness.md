---
status: in-progress
---

# Harness Kit Release-Readiness Implementation Plan

**Input findings: 24**

**Goal:** Bring the public harness-kit template to release quality — add licensing/hygiene, fix installer/doc parity, correct golden-principle integrity, land the vault "dynamic harness" bundle (skills + Claude Code hooks + reference-doc templates) with all Claude Code protocol bugs fixed, and add self-verifying CI so the kit demonstrates its own discipline.

**Architecture:** The repo is a template/starter kit consumed by book readers, not an application. Every file is copy-pasted into reader projects, so clarity and macOS+Linux portability outrank cleverness. Work is layered: hygiene → installer/docs → principle integrity → land bundle → CI. Bundle files are copied from the read-only vault and adapted (never edited in place). No new frameworks: hooks stay bash + one Python file with the standard library only.

**Tech Stack:** Bash (git hooks, installer, smoke test), Python 3 standard library (PreToolUse gate + PostToolUse record hook, and structural JSON parsing inside `stop-verify.sh`), GitHub Actions (shellcheck + `py_compile` + smoke on Linux, macOS, and a pre-commit-framework job), Markdown/JSON templates.

> **Revision note (Codex round 1):** This plan was revised after a cross-model review returned 12 findings, all accepted. The major redesigns: the checklist hook now records verifications at **PostToolUse** (after a command runs) and gates at **PreToolUse**, so a failing `npm test` can no longer pre-satisfy the gate; the Stop hook uses a bounded loop policy (re-run, then warn-allow) with structural JSON parsing; the installer coexists with existing hooks by **chaining** them (never disabling), honors `core.hooksPath`, and refuses to falsely claim success. See the second traceability table ("Codex round-1 findings") for the full mapping.
>
> **Revision note (Codex round 2):** A second cross-model review returned 6 blockers (R1–R6) + 7 secondaries (S1–S7), all accepted, plus **verified protocol-fact corrections** that supersede round-1: `PostToolUseFailure` **exists** and `PostToolUse` fires **only on success**, so the checklist registers only `PostToolUse`, drops `tool_response`, and keys state on the event `cwd`. Round-2 hardening: anchored `should_record` command validation (R1); a second, field-independent Stop loop guard (per-session block counter, R2); installer refusal of a `core.hooksPath` escape or a symlinked hook target (R3); content+mode idempotency assertions (R4); an internal `HARNESS_KIT_HOOK_MODE` seam plus a third pre-commit CI job for deterministic tests (R5); and a truthful `HOOKS_ACTIVE`-keyed install banner (R6). The smoke suite grew from 16 to **22** assertions. See the third traceability table ("Codex round-2 findings") for the full mapping.
>
> **Revision note (Codex round 3):** A third review returned 7 blockers (R3-1..R3-7) + secondaries + a plan-doc delta, all accepted, with three **externally verified** facts (checked, not transcribed): pre-commit refuses to install when `core.hooksPath` is set (→ smoke hermeticity via `GIT_CONFIG_GLOBAL/SYSTEM=/dev/null`, installer `pre-commit install || return 1`, pinned CI version — R3-1); a linked worktree's hooks live under `--git-common-dir` (→ containment now allows it, and resolves the path *before* any mkdir — R3-2); and the CC docs **do** document Stop exit-2 blocking (→ corrects the earlier "docs-silent" wording; the two Stop guards stay as defense-in-depth — R3-7). Other round-3 fixes: no inline-`cd` verification escape + project-root state keying + broadened commit detection (R3-3); the chaining/idempotency assertions that never actually landed, now including `.git/hooks` in the content+mode snapshot (R3-4); shellcheck-clean smoke and installer (R3-5); complete-config foreign detection that also blocks `precommit` mode (R3-6); a validated, per-(session,project) Stop counter (R3-7); plus `load_state` value-type checks (S3′) and a fail-closed state dir (S4′). The smoke suite grew from 22 to **30** assertions. See the fourth traceability table ("Codex round-3 findings") for the full mapping.
>
> **Revision note (Codex round 4):** A fourth review returned 6 blockers (R4-1..R4-6) + 4 corrections + a plan-doc delta, all accepted; this was the penultimate gate, so each was fixed with the **conservative** option. The escape fixes: `project_root` now resolves the git top-level from the event `cwd` **first** (`CLAUDE_PROJECT_DIR` demoted to a bounded fallback), closing a cross-repo authorization escape (R4-1); `install_raw_git_hooks` returns non-zero with per-hook rollback on any write failure instead of falsely reporting active (R4-2); a pre-existing `.pre-commit-config.yaml` is foreign unless **byte-identical** (`cmp -s`), replacing the earlier substring checks (R4-3); the state dir **fails closed** on unwritable-or-insecure (every `OSError` wrapped as `StateDirError`, `makedirs` without `exist_ok` + TOCTOU re-`lstat`, gate denies) (R4-4); the Stop hook never loses either loop guard on a state-dir error (embedded helper returns `""`, never raises) (R4-5); and a malformed `# shellcheck` line was reworded (R4-6). Corrections: the anchored allowlist gained `python3 -m pytest`/`flake8`/`./node_modules/.bin/tsc`/`cargo check` (C1); smoke gained a linked-worktree success case and an external-`core.hooksPath` refusal case (C2); the chain marker is matched with `grep -Fxq` (C3); and the round-3 table's header/rows/summary were reconciled (D-count). The smoke suite grew from 30 to **37** assertions. See the fifth traceability table ("Codex round-4 findings") for the full mapping.
>
> **Revision note (Codex round 5):** A fifth, user-approved scoped review returned 3 blockers + an assertion note + 4 stale-prose spots, all accepted with the conservative option. `install.sh` now **refuses to run from a linked worktree** (`--absolute-git-dir` ≠ `--git-common-dir`), because its shared hooks would carry worktree-local paths and break the primary and sibling worktrees (R5-1); the two raw hooks are written as **one snapshot/restore transaction** so a mid-install failure restores BOTH (a marker-owned non-executable hook is `chmod`-repaired in-transaction) instead of leaving pre-commit active while the banner says inactive (R5-2); and both state-dir helpers validate ownership + non-symlink **before any `chmod`**, closing a create-window TOCTOU (R5-3). The external-`core.hooksPath` smoke assertion is now a recursive content+mode snapshot diff (SNAP), and four Context-Brief/Failure-Modes prose spots were synced to the round-3/4 design (P1–P4). The smoke suite grew from 37 to **40** assertions. See the sixth traceability table ("Codex round-5 findings") for the full mapping.

---

## Scope Challenge

Per global GP #14 (Don't Scope Creep) and global GP #17 (Right-Sized Code) — the author's `~/.claude/golden-principles.md`, distinct from the kit's own principles doc — each work package was checked against "does a book reader need this to safely adopt the kit?":

- **Kept:** licensing, `.gitignore`, installer/doc parity, principle-number integrity, the dynamic-harness bundle, and CI. All 24 findings are defects a reader would hit or be misled by on day one.
- **Deliberately NOT built:** the loop-detection hook that kit GP #8 (Bounded Iteration) falsely advertises (finding 12 removes the false claim rather than building the hook — building it is unrequested speculative complexity). No Makefile / `make test` entrypoint (finding 24 decision below). No test framework — the smoke test is plain bash, no bats.
- **Boundary risk flagged:** adding any build marker (`Makefile`, `Justfile`, `pyproject.toml`, …) to the kit's own root would flip harness-kit from "docs-only" to "requires stamp" under its own `pre-commit-verify.sh` logic, forcing every contributor commit to carry a `.harness-verified` stamp. This plan keeps the repo docs-only on purpose (see finding 24).

No task here touches auth, payments, schemas, or public API contracts; none needs a "Ask First" pause beyond what the findings already authorize.

## Context Brief

> Non-obvious project context implementers need.

- **Environment:** Public template repo (`github.com/cmillstead/harness-kit`), companion to *The Harness Engineering Playbook* (Cevin Millstead, 2026). Files here are consumed verbatim by readers — a bug ships to every reader who runs `install.sh`.
- **Sacred paths:** The vault directory `/Users/cevin/Documents/obsidian-vault/AI/ebook/harness-engineering/harness-kit-updates/` is READ-ONLY source material. COPY from it; NEVER edit it. The repo's own `.claude/settings.local.json` is local dev config, not part of the kit — do not modify or ship it.
- **Decision history (user-fixed, do not revisit):** License = MIT, holder "Cevin Millstead", year 2026. The kit's `docs/golden-principles.md` lands kit GP #17 (Define exceptions by purpose, not format) and kit GP #18 (The thought "this is too simple" is the signal) → doc becomes 18 principles. (These are the KIT's new principles — not to be confused with the author's global GP #17 Right-Sized Code / #18.)
- **Known landmines (Claude Code hook protocol — VERIFIED against the July 2026 docs; these override any conflicting round-1 text):**
  - Every hook receives, in its stdin JSON: `session_id`, `hook_event_name`, `tool_name`, `tool_input`, `tool_use_id`, `cwd`, `transcript_path`, `permission_mode`. Use the event's **`cwd`** field for the repo-root component of state keys (NOT `os.getcwd()`). One script can serve multiple events by branching on `hook_event_name`.
  - **`PostToolUse` and `PostToolUseFailure` both exist.** `PostToolUse` fires ONLY after a tool call **succeeds**; `PostToolUseFailure` after it fails. So the checklist records at **PostToolUse only** — the event firing IS the success signal, needing NO `tool_response`/`interrupted` inspection, and `PostToolUseFailure` is deliberately NOT registered. (This CORRECTS the round-1 claim that PostToolUseFailure does not exist — it does.)
  - **PreToolUse deny:** BOTH `{"decision": "block", "reason": "..."}` and `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}` are documented-valid. We use the `hookSpecificOutput` form (preferred).
  - **settings.json** nests matcher-groups: `{"hooks": {"EventName": [{"matcher": "...", "hooks": [{"type": "command", "command": "..."}]}]}}`. The `matcher` is a tool-name filter for PreToolUse/PostToolUse (`"Bash"`); OMIT it for `Stop`. `${CLAUDE_PROJECT_DIR}` is BOTH expanded inside hook `command` strings AND exported as an env var to the hook process.
  - **Stop-hook exit-2 blocking IS documented** (verified against the live docs, round 3: the "Exit code 2 behavior per event" table lists Stop → "Prevents Claude from stopping, continues the conversation"), and `stop_hook_active` is provided so a hook can detect it is re-running after its own block. This CORRECTS the round-1/round-2 "docs-silent" claim. We still keep a second, field-independent loop guard (a per-(session, project) block counter) as **defense in depth** — so a payload missing the field, or a future shape drift, still cannot loop unbounded (Task 4).
  - Claude Code skills live at `.claude/skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`).
- **Portability:** macOS `stat -f %m` vs Linux `stat -c %Y` are already handled in `pre-commit-verify.sh`; keep that pattern. `touch -t CCYYMMDDhhmm` works on both BSD (macOS) and GNU; target shells include macOS's default **bash 3.2**, so avoid bash-4 features (`mapfile`, associative arrays). Do not assume `jq` — `python3` IS already a kit dependency, so parse CC JSON with `python3` (stdlib `json`).
- **State-file safety (checklist hook):** state lives in a per-user `0700` directory under the system temp dir, validated via `lstat` (real dir, current-uid-owned, mode `0700`, not a symlink) and **fails closed** — it raises `StateDirError` and the gate then denies (never a silent `mkdtemp` fallback that would mis-scope state) if the dir is insecure or unwritable (S4′/R4-4); the dir is validated **before** any `chmod`, so a symlink planted in the create window is never followed (R5-3). One `0600` file per `(session_id, project_root)`, where `project_root` is the git top-level of the event `cwd` resolved first (`CLAUDE_PROJECT_DIR` only a fallback — R3-3/R4-1); written to a temp name and `os.replace`d atomically; only `{category, time}` is stored — never command text.

## Project-Specific Eval Criteria

> Auditors MUST verify these beyond their standard lens.

### Context-derived (this session)
- [ ] No shipped hook or script introduces a non-stdlib dependency (no `jq`, no pip/npm packages). Hooks stay bash + stdlib Python 3.
- [ ] Every Claude Code hook honors its protocol exactly: Stop → exit 2 + stderr on first-stop red, warn-allow (exit 0) on active-stop red, `stop_hook_active` parsed structurally, PLUS a field-independent per-(session, project) block-counter fallback as defense-in-depth (the CC docs DO document Stop exit-2 blocking — verified round 3); PreToolUse → `hookSpecificOutput`/`permissionDecision` JSON + `session_id` from stdin.
- [ ] **Recording happens only when the `PostToolUse` event fires** (success-only by protocol) — no `tool_response` inspection; `PostToolUseFailure` is not registered.
- [ ] **Anchored command validation:** a command is recorded only if it contains no `||`, `;`, `|`, `&`, `$(`, backtick, or newline, and every `&&`-separated segment matches an approved verification command anchored at segment start — **no inline-`cd` allowance** (R3-3). `npm test || true`, `echo npm test`, `FOO=bar npm test` are all rejected.
- [ ] **Checklist state files are `0600` inside a `0700` per-user dir** (validated via `lstat`; **fail-closed** — every `OSError` is wrapped as `StateDirError` and the gate then denies with a diagnostic — if the dir is insecure **or unwritable**, R4-4), written atomically, keyed by `sha256(session_id + project_root)` where `project_root` is the git top-level of the event `cwd` **first**, with `CLAUDE_PROJECT_DIR` only a bounded fallback (R3-3 / R4-1), storing only `{category, time}` — never command text; `load_state` resets to empty on any shape **or value-type** mismatch.
- [ ] **Existing git hooks are chained, never disabled** — a foreign hook is preserved as `<hook>.harness-preserved` and invoked first (non-zero propagates); our wrappers carry the exact marker `# harness-kit hook`; the installer preflights BOTH hooks (symlink + preserved-name collision) before writing either, then writes them as **one transaction** — both snapshotted, and on any failure BOTH restored (R5-2).
- [ ] The installer honors `core.hooksPath` **only when the resolved hooks dir stays under the top-level, git dir, OR git common dir** — resolving the path with `realpath` **before creating anything**, refusing a shared/global path or a symlinked target; **refuses to run from a linked worktree** (R5-1 — shared hooks would carry worktree-local paths); runs only from the git top-level; validates `HARNESS_KIT_HOOK_MODE` ∈ {direct, precommit, auto}; blocks a foreign/partial config in BOTH auto and precommit; and its closing banner tells the truth — success only when hooks are active, else a reason-specific "NOT active" message (`worktree`/`refused`/`foreign`).
- [ ] No vault file was modified (source is read-only). All bundle files are copies.
- [ ] The kit's own repo root gains NO build marker (`Makefile`, `Justfile`, `pyproject.toml`, `package.json`, …) — it must remain "docs-only" so its own commits don't demand a stamp.
- [ ] Every pointer in template files (`AGENTS.md`, generated `CLAUDE.md`, `.cursor/rules/harness.md`) resolves to a file `install.sh` actually creates.
- [ ] All `*.sh` files and `install.sh` pass `shellcheck` with no warnings; intentional word-splitting is annotated with a scoped `# shellcheck disable=SC2086` and a reason.
- [ ] Golden-principle numbers are internally consistent: "Verify Before Claiming Done" is #7 everywhere; the doc has exactly 18 principles; README says "18".
- [ ] `pre-commit-verify.sh` rejects both stale (> 30 min) AND future-dated stamps (clock-skew guard), deleting the stamp and messaging the user in both cases.

## What Already Exists

- `README.md` (86 lines), `AGENTS.md` (template, 69 lines, **two** `## Code Style` sections), `install.sh` (147 lines), `.pre-commit-config.yaml`.
- `docs/golden-principles.md` (16 principles; #8 Bounded Iteration falsely claims a loop-detection hook), `docs/harness-philosophy.md`, `docs/code-style.md`.
- `hooks/no-mocks.sh`, `hooks/pre-commit-verify.sh` (cites GP "#8" for verification — wrong, should be #7), `hooks/post-commit-cleanup.sh`, `hooks/pre-completion-checklist.py` (dark feature: not installed, not documented; reads `CLAUDE_SESSION_ID` from env; emits legacy `{"decision":"block"}`; cites GP "#8").
- `.harness-verified` — 0-byte stamp, **tracked in git** (should be ignored). `.DS_Store` — present on disk, untracked.
- **Absent:** `LICENSE`, `.gitignore`, `tests/`, `.github/`, `skills/`, `docs/decision-record-template.md`, `docs/eval-template.md`, `docs/escape-hatch-audit.md`, `docs/context-inheritance-audit.md`, `hooks/stop-verify.sh`, `hooks/settings-snippet.json`, `skills/review.md`.

## NOT In Scope (user-scoped out)

- README link to the book / purchase page.
- `templates/` directory of Ch. 20 copy-paste starter templates.
- File→chapter→maturity-level cross-reference map.
- `v1.0.0` tag + `CHANGELOG` (done at release time, not here).
- Book-side edits. **Flag for the user:** `talking-points.md` (and any vault material) that says "16 golden principles" becomes stale once the doc goes to 18. The vault is out of scope this session — the user must reconcile the book copy separately.
- **Install manifest** (a recorded list of installed files for a precise uninstall) — **deferred to v1.1** (Codex finding 5). Rationale: the enumerated safe-uninstall in the README covers the common case; a manifest adds install-time state and its own staleness failure mode, which is not worth it before v1.0.
- **`.harness/verify.sh` single-command verification redesign** for the Stop hook (one project-defined entrypoint instead of auto-detecting `npm test`/`pytest`/`cargo`) — **deferred to v1.1 design** (Codex finding 9). Rationale: it is a cleaner model but a design change, not a release-blocking fix; the cheap per-command guards in Task 4 make the current auto-detection safe enough to ship.

## Failure Modes

| Failure mode | Where | Trigger | Mitigation in this plan |
|---|---|---|---|
| Stamp race / reuse | `pre-commit-verify.sh` | A stamp created for one change is reused by a later commit within the 30-min window | Stamp is single-use — `post-commit-cleanup.sh` deletes it after every commit; 30-min expiry documented (finding 10). No change to logic; documented so readers understand it. |
| Stale-stamp deletion | `pre-commit-verify.sh` (stale branch) | Blocked stale stamp is deleted, surprising a retrying user | Existing behavior is correct (forces re-verify); README now documents expiry + deletion so it is not surprising. |
| Existing git hook disabled | `install.sh` fallback path | Reader's repo already has `pre-commit`/`post-commit` hooks | Codex 4: a foreign hook is **chained**, not moved aside — preserved as `<hook>.harness-preserved` and invoked first (non-zero propagates), then harness checks run. Installer refuses (no overwrite) if the preserved name already exists. Ownership by exact marker `# harness-kit hook`. |
| Checklist masked-failure record | `pre-completion-checklist.py` | A *successful* Bash call whose text contains a verification substring but masks/chains failure (`npm test \|\| true`, `npm test; true`, `false \|\| echo npm test`) would record a verification | Codex R2-R1: PostToolUse-only recording (success by protocol, no `tool_response` needed) PLUS **anchored validation** — reject any command with `\|\|`/`;`/`\|`/`&`/`$(`/backtick/newline; every `&&` segment must match an approved verification anchored at start — there is **no** leading-`cd` allowance (R3-3), so `cd ../other && npm test` cannot authorize this repo. Smoke adds 3 negative cases. |
| Installer false success | `install.sh` | Existing `.pre-commit-config.yaml` → `pre-commit install` runs against the user's config, harness hooks silently inactive; a **partial** merge passes a one-line grep as "complete"; `precommit` mode skips the foreign branch; or any branch leaves hooks unwired but the banner still says "installed successfully" | Codex 3c + R2-R6 + R3-6 + **R4-3**: `CONFIG_FOREIGN` is true unless a pre-existing `.pre-commit-config.yaml` is **byte-identical** to the shipped one (`cmp -s`) — a partial or reordered merge is treated as foreign; a foreign config blocks BOTH `auto` and `precommit`; installer tracks `HOOKS_ACTIVE` + `INACTIVE_REASON` and the **closing banner tells the truth** (reason-specific text). Smoke asserts the foreign-config banner, installer exit 0, a near-miss config rejected, and that the foreign config is unmodified. |
| `core.hooksPath` escape | `install.sh` | Custom `core.hooksPath` points at a shared/global hooks dir, or the target hook is a symlink → installer writes outside the repo or clobbers a link; **linked worktrees** legitimately place hooks under the common dir | Codex 3b + R2-R3 + R3-2 + **R5-1**: resolve `git rev-parse --git-path hooks` with `realpath` **before any mkdir**; allow containment under toplevel OR `--absolute-git-dir` OR `--git-common-dir`, else REFUSE; preflight symlink + preserved-name collision for BOTH hooks before writing either; explicit `direct` mode makes a refusal fatal. **R5-1:** installing from a *linked* worktree is refused entirely (shared hooks would carry worktree-local paths and break the primary/sibling worktrees), so the common-dir containment clause is now only exercised by the primary worktree. |
| Uninstall destructiveness | README uninstall | `rm -rf` of shared dirs / blanket `pre-commit uninstall` removes user files/hooks | Codex 5 + **R2-R6**: uninstall is now a **manual review-before-removal CHECKLIST** (not an unconditional script) — each item carries an "only if you didn't have/customize it" caveat, directory removal is `rmdir`-if-empty, and the hook restore is a marker-gated command that restores `<hook>.harness-preserved`. |
| CI false-green | `tests/smoke.sh` + `ci.yml` | Test asserts nothing; or passes/fails only on one install path | Explicit exit-code AND message assertions incl. **negative** cases; installer/baseline fatal via `run_or_die`; `HARNESS_KIT_HOOK_MODE` seam makes the path deterministic — CI runs smoke in **direct** (raw hooks) on Linux+macOS AND in **precommit** (framework) on a third Linux job; behavior-level assertions are identical because both paths run the same scripts. |
| Stop hook infinite loop | `hooks/stop-verify.sh` | Hook blocks, agent retries forever; or a payload omits `stop_hook_active` / the shape drifts | Codex 2 + R2-R2 + **R3-7**: TWO independent guards (defense-in-depth — CC docs DO document Stop exit-2 blocking): (1) structural `stop_hook_active` parse → active-stop warn-allow; (2) a per-(session, project) block counter in the **lstat-validated** 0700 dir → if blocked ≥2× in 10 min, warn-allow regardless; counter lines numeric-validated, expired entries pruned. Green run resets it. First red stop still blocks (exit 2 + stderr). |
| Stamp clock-skew / expiry rounding | `pre-commit-verify.sh` | Future-dated stamp yields negative age and slips past the stale check; truncated-minutes comparison lets a 30m00s-plus stamp pass | Codex 12 + **S1**: reject age `< 0` (block, delete, "in the future"); compare **in seconds** (`age_seconds > MAX_AGE_MINUTES*60`), keeping minutes only in the message. |
| Silent Claude-hook no-op | `pre-completion-checklist.py`, `settings-snippet.json` | Wrong session key collapses sessions; legacy JSON shape ignored; flat settings schema not parsed | Findings 13 + 15: `sha256(session_id + project_root)` state key (project_root = git top-level of the event `cwd` first, R3-3/R4-1), `hookSpecificOutput` deny, real nested settings schema with Stop/PreToolUse/PostToolUse groups. |

## File Structure

**Create:** `LICENSE`, `.gitignore`, `hooks/stop-verify.sh`, `hooks/settings-snippet.json`, `skills/review.md`, `docs/decision-record-template.md`, `docs/eval-template.md`, `docs/escape-hatch-audit.md`, `docs/context-inheritance-audit.md`, `tests/smoke.sh`, `.github/workflows/ci.yml`. (Installer also generates `.claude/skills/review/SKILL.md` in consumer repos — no repo source file; see Task 9.)

**Modify:** `docs/golden-principles.md`, `hooks/pre-commit-verify.sh`, `hooks/pre-completion-checklist.py`, `AGENTS.md`, `install.sh`, `README.md`.

**Delete / untrack:** `.harness-verified` (untrack + remove), `.DS_Store` and `docs/.DS_Store` (remove from disk).

**Dependency order:** T1 (branch + hygiene) → T2, T3, T4, T5, T6, T7, T8 (independent content tasks) → T9 (install.sh, needs bundle files present) → T11a (smoke, needs final hooks + installer) → T11b (CI, needs smoke) → T10 (README, needs final file set + CI workflow name for the badge). T9/T11a/T11b/T10 are the ordered tail.

**Implementer note — command hygiene (round-3 advisory):** several `Run:` lines in this plan are written as compound one-liners for brevity (notably T4 Step 3, T7 Step 2, and T9 Step 13, which chain `cd`/`&&`/`;`/pipes). These are illustrations of intent, not literal single Bash invocations. When executing, split them into one command per Bash call (or wrap the throwaway setup in a script file), per the command-hygiene rule — a compound command defeats the per-command permission allowlist and prompts on every run.

---

### Task 1: Feature branch + Work Package A (licensing & hygiene)

**Findings:** 1, 2, 3, 4

**Files:**
- Create: `LICENSE`, `.gitignore`
- Untrack + delete: `.harness-verified`
- Delete from disk: `.DS_Store`, `docs/.DS_Store`

**Model:** haiku
**Advisory:** None

- [ ] **Step 1: Create the feature branch** (never commit to `main` — CLAUDE.md).

Run: `git checkout -b release-readiness`
Expected: `Switched to a new branch 'release-readiness'`

- [ ] **Step 2: Create `LICENSE`** (MIT, exact text):

```text
MIT License

Copyright (c) 2026 Cevin Millstead

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Create `.gitignore`** (Codex 7 — also ignore Python bytecode from `py_compile`/hook runs):

```gitignore
# macOS
.DS_Store

# Python bytecode (py_compile, hook runs)
__pycache__/
*.pyc

# Harness verification stamp (single-use, never committed)
.harness-verified
```

- [ ] **Step 4: Untrack the stamp and remove it from disk** (finding 3).

Run: `git rm --cached .harness-verified`
Expected: `rm '.harness-verified'`
Run: `rm -f .harness-verified`

- [ ] **Step 5: Remove the stray `.DS_Store` files** (finding 4; Codex 7 — `docs/.DS_Store` also exists on disk).

Run: `rm -f .DS_Store`
Run: `rm -f docs/.DS_Store`

- [ ] **Step 6: Stage the new files, then verify hygiene** (Codex S2 — stage BEFORE the status check so the expected output matches reality; the stamp deletion is already staged by `git rm --cached` in Step 4, and re-adding a deleted+ignored path would error, so stage only the two new files).

Run: `git add LICENSE .gitignore`
Run: `git status --porcelain`
Expected: `A  LICENSE`, `A  .gitignore`, and `D  .harness-verified`; no `.DS_Store`, no `docs/.DS_Store`, and no `.harness-verified` listed as untracked (`??`).
Run: `git check-ignore .DS_Store docs/.DS_Store .harness-verified`
Expected: all three paths echoed back (proving they are now ignored).

- [ ] **Step 7: Commit.**

```bash
git commit -m "chore: add MIT LICENSE, .gitignore; untrack verification stamp"
```

---

### Task 2: Golden-principles integrity — remove false enforcement, add kit GP #17/#18

**Findings:** 12, 20 (doc portion)

**Files:**
- Modify: `docs/golden-principles.md`

**Model:** haiku
**Advisory:** None

- [ ] **Step 1: Remove the false enforcement claim in #8** (finding 12). Delete this exact line (currently line 31):

```markdown
- **Enforcement**: loop detection hook tracks repeated failures
```

Kit GP #8's (Bounded Iteration) body text stays; only the fabricated `- **Enforcement**` line is removed (no loop-detection hook exists in the kit, and we are NOT building one).

- [ ] **Step 2: Append kit principles #17 and #18** after `## 16. Naming Is Architecture` (end of file). Text adapted from the vault `AGENTS-additions.md`, formatted to match the file's existing `## N. Title` heading style:

```markdown

## 17. Define Exceptions by Purpose, Not Format
"Markdown docs are OK to edit directly" sounds clear — until the agent classifies your SKILL.md as a markdown doc. Define what's exempt by what it does (documentation), not what it is (.md file).

## 18. The Thought "This Is Too Simple" Is the Signal to Use the Process
Agents have a strong prior toward efficiency. When they see a trivial task, they invent reasons to skip the workflow. Name this tendency explicitly so the agent recognizes it as a compliance trigger, not a valid optimization.
```

- [ ] **Step 3: Verify the count.**

Run: `grep -c '^## [0-9]' docs/golden-principles.md`
Expected: `18`
Run: `grep -n 'loop detection hook' docs/golden-principles.md`
Expected: no output (the false claim is gone).

- [ ] **Step 4: Commit.**

```bash
git add docs/golden-principles.md
git commit -m "docs: remove nonexistent loop-detection enforcement claim; add golden principles 17-18"
```

---

### Task 3: Redesign the verification hooks — checklist record/gate split, state hardening, stamp-age guard

**Findings:** 11, 13 (code portion); Codex 1, 10, 12

**Files:**
- Modify: `hooks/pre-commit-verify.sh` (GP #7 citation + future-dated stamp rejection)
- Rewrite: `hooks/pre-completion-checklist.py` (full redesign — record at PostToolUse, gate at PreToolUse, hardened state)

**Model:** sonnet (this task grew from a citation edit to a hook redesign — clearly sonnet, and the largest of the hook tasks)
**Advisory:** None (template hook, not auth/payment — no `/second-opinion` needed)

- [ ] **Step 1: `pre-commit-verify.sh` — fix the GP citation** (finding 11). "Verify Before Claiming Done" is kit GP **#7**, not #8. Replace (currently line 70):

Old: `    echo "Golden Principle #8: Verify Before Claiming Done."`
New: `    echo "Golden Principle #7: Verify Before Claiming Done."`

- [ ] **Step 2: `pre-commit-verify.sh` — reject future-dated stamps and compare expiry in seconds** (Codex 12 + S1). Replace the age computation + stale check (currently lines 88-106):

Old:
```bash
if [ "$(uname)" = "Darwin" ]; then
    stamp_time=$(stat -f %m "$STAMP_FILE")
else
    stamp_time=$(stat -c %Y "$STAMP_FILE")
fi
now=$(date +%s)
age=$(( (now - stamp_time) / 60 ))

if [ "$age" -gt "$MAX_AGE_MINUTES" ]; then
    echo "============================================"
    echo "BLOCKED: Verification stamp is stale (${age}m old)"
    echo "============================================"
    echo ""
    echo "Re-run tests and linting — the stamp expires after $MAX_AGE_MINUTES minutes."
    echo "  npm test && npm run lint && touch $STAMP_FILE"
    echo ""
    rm -f "$STAMP_FILE"
    exit 1
fi
```
New:
```bash
if [ "$(uname)" = "Darwin" ]; then
    stamp_time=$(stat -f %m "$STAMP_FILE")
else
    stamp_time=$(stat -c %Y "$STAMP_FILE")
fi
now=$(date +%s)
age_seconds=$(( now - stamp_time ))

# Reject a future-dated stamp (clock skew, or a hand-set mtime) — a negative
# age would otherwise slip past the stale check below.
if [ "$age_seconds" -lt 0 ]; then
    echo "============================================"
    echo "BLOCKED: Verification stamp timestamp is in the future"
    echo "============================================"
    echo ""
    echo "The stamp's timestamp is ahead of the current time (clock skew?)."
    echo "Re-run tests and linting to create a fresh stamp:"
    echo "  npm test && npm run lint && touch $STAMP_FILE"
    echo ""
    rm -f "$STAMP_FILE"
    exit 1
fi

# Compare in SECONDS (truncated minutes would let a 30m59s stamp pass).
if [ "$age_seconds" -gt "$(( MAX_AGE_MINUTES * 60 ))" ]; then
    age=$(( age_seconds / 60 ))
    echo "============================================"
    echo "BLOCKED: Verification stamp is stale (${age}m old)"
    echo "============================================"
    echo ""
    echo "Re-run tests and linting — the stamp expires after $MAX_AGE_MINUTES minutes."
    echo "  npm test && npm run lint && touch $STAMP_FILE"
    echo ""
    rm -f "$STAMP_FILE"
    exit 1
fi
```

- [ ] **Step 3: Rewrite `hooks/pre-completion-checklist.py` entirely.** This replaces the whole file. Redesign (Codex 1/10 + R2-R1 + R3-3 + R4-1/R4-4): one script serves **PreToolUse (gate only)** and **PostToolUse (record only)** on `hook_event_name`. `PostToolUse` fires ONLY on success (verified fact), so recording needs no `tool_response` inspection; instead recording uses **anchored command validation** (R2-R1) with **no inline-`cd` allowance** (R3-3). State is `0600` in a `0700` per-user dir (validated via `lstat`; **fail-closed** — raises, and the gate then emits a deny *decision* — if the dir is insecure OR unwritable, S4/R4-4, with post-creation revalidation to close the TOCTOU), keyed by `sha256(session_id + project_root)` where `project_root` is the git top-level of the event `cwd` **first**, falling back to `${CLAUDE_PROJECT_DIR}` only when git resolution fails and `cwd` is inside it (R4-1 — a stale `CLAUDE_PROJECT_DIR` must not authorize another repo); stores only `{category, time}`; `load_state` fully validates shape **and value types** (S3). Full file contents:

```python
#!/usr/bin/env python3
"""Claude Code verification hook: gate commits, record verifications.

One script, two Claude Code events (selected via hook_event_name in stdin):

  PreToolUse  (matcher: Bash) — GATE only. Before `git commit`/`git push`,
              deny if this session has not recorded BOTH a test and a lint
              run for this working directory. Never records anything.
  PostToolUse (matcher: Bash) — RECORD only. PostToolUse fires ONLY after a
              tool call SUCCEEDS (PostToolUseFailure fires on failure and is
              NOT registered), so the event itself is the success signal — no
              exit-code/tool_response inspection is needed. A command is
              recorded only if it passes ANCHORED validation (below), which
              rejects masked/chained forms like `npm test || true`.

Anchored validation: reject any command containing || ; | & $( ` or a newline;
split the rest on && and require EVERY segment to match an approved verification
command anchored at its start. There is deliberately no leading-`cd` allowance:
`cd other-repo && npm test` would run tests elsewhere yet authorize this repo.

State: a per-user 0700 dir under the system temp dir (validated via lstat; if it
is not a private self-owned dir, or cannot be created, the hook FAILS CLOSED).
One 0600 file per (session_id, project_root), where project_root is the git
top-level of the event cwd (CLAUDE_PROJECT_DIR is only a fallback, and only when
cwd is inside it). Only {category, time} is stored — never command text.
"""

import glob
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import time

STALE_SECONDS = 7200          # forget verifications older than 2 hours
RECENT_SECONDS = 1800         # the gate looks back 30 minutes

# Approved verification commands, anchored at a segment start (args allowed).
# Kept in sync with the Stop hook's command set: pytest via `python3 -m pytest`,
# `flake8`, `cargo check`, and the project-local `./node_modules/.bin/tsc`.
APPROVED_RE = re.compile(
    r"^(npm test|npm run test|npm run lint|npx jest|npx vitest|npx eslint|"
    r"pytest|python3 -m pytest|ruff check|flake8|mypy|"
    r"cargo test|cargo clippy|cargo check|go test|"
    r"make test|make lint|make check|shellcheck|"
    r"tsc --noEmit|\./node_modules/\.bin/tsc|bash -n)\b"
)
TEST_RE = re.compile(
    r"\b(npm test|npm run test|npx jest|npx vitest|pytest|cargo test|"
    r"go test|make test|bash -n)\b"
)
LINT_RE = re.compile(
    r"\b(npm run lint|npx eslint|tsc --noEmit|mypy|ruff check|flake8|"
    r"cargo clippy|cargo check|make lint|make check|shellcheck)\b"
)
# Match a git commit/push even with a path prefix (/usr/bin/git) or leading
# options (`git -C . commit`, `git -c k=v push`). Over-matching only widens the
# gate, which is the safe direction (R3-3).
COMMIT_PATTERN = re.compile(r"\bgit\b(?:\s+-\S+(?:\s+\S+)?)*\s+(?:commit|push)\b")

PROJECT_MARKERS = [
    "package.json", "tsconfig.json", "deno.json",
    "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt",
    "Pipfile", "tox.ini", "Cargo.toml", "go.mod",
    "pom.xml", "build.gradle", "build.gradle.kts", "build.sbt",
    "Directory.Build.props", "Gemfile", "Rakefile", "composer.json",
    "Package.swift", "pubspec.yaml", "mix.exs",
    "stack.yaml", "cabal.project",
    "CMakeLists.txt", "meson.build", "configure.ac",
    "build.zig", "deps.edn", "project.clj", "Project.toml",
    "Makefile", "Justfile",
]
GLOB_MARKERS = ["*.csproj", "*.sln", "*.xcodeproj", "*.nimble"]


class StateDirError(Exception):
    """The per-user state dir exists but is not a private, self-owned dir."""


def _dir_is_secure(info) -> bool:
    return (
        stat.S_ISDIR(info.st_mode)
        and not stat.S_ISLNK(info.st_mode)
        and info.st_uid == os.getuid()
        and stat.S_IMODE(info.st_mode) == 0o700
    )


def state_dir() -> str:
    # ONE stable per-user dir so a verification recorded at PostToolUse is still
    # found by the PreToolUse gate. FAIL CLOSED (raise StateDirError) if it is not
    # a real, self-owned, non-symlink 0700 dir — OR if creating it fails (R4-4:
    # os.makedirs/os.chmod OSError must not slip past as an ALLOW at the gate).
    base = os.path.join(tempfile.gettempdir(), f"claude-harness-{os.getuid()}")
    try:
        os.makedirs(base, mode=0o700)   # no exist_ok — we validate the result below
    except FileExistsError:
        pass                            # already present, or lost a create race
    except OSError as exc:
        raise StateDirError(base) from exc
    # R5-3: lstat and confirm a real, self-owned, NON-symlink dir BEFORE any chmod,
    # so a symlink planted in the create window can never have its TARGET chmod'd.
    try:
        info = os.lstat(base)
    except OSError as exc:
        raise StateDirError(base) from exc
    if not (
        stat.S_ISDIR(info.st_mode)
        and not stat.S_ISLNK(info.st_mode)
        and info.st_uid == os.getuid()
    ):
        raise StateDirError(base)       # not our own real dir — refuse WITHOUT touching it
    # Only now, on a validated self-owned real dir, tighten the mode if needed and
    # RE-lstat before the full secure check (owner + non-symlink + exactly 0700).
    if stat.S_IMODE(info.st_mode) != 0o700:
        try:
            os.chmod(base, 0o700)
            info = os.lstat(base)
        except OSError as exc:
            raise StateDirError(base) from exc
    if not _dir_is_secure(info):
        raise StateDirError(base)
    return base


def _git_toplevel(cwd: str):
    # Read-only resolution of the git top-level of the EVENT cwd. Returns a real
    # path or None. This is the repo the command actually ran in.
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode == 0 and result.stdout.strip():
        return os.path.realpath(result.stdout.strip())
    return None


def project_root(cwd: str) -> str:
    # R4-1: resolve the git top-level of the EVENT cwd FIRST — that is the repo
    # the command ran in, and it cannot be spoofed by a stale CLAUDE_PROJECT_DIR
    # left over after Claude cd'd into a different repo in an earlier tool call.
    # Only fall back to CLAUDE_PROJECT_DIR when git resolution fails AND cwd is
    # inside it; otherwise use the cwd itself.
    cwd_real = os.path.realpath(cwd)
    top = _git_toplevel(cwd)
    if top:
        return top
    env_root = os.environ.get("CLAUDE_PROJECT_DIR")
    if env_root:
        env_real = os.path.realpath(env_root)
        if cwd_real == env_real or cwd_real.startswith(env_real + os.sep):
            return env_real
    return cwd_real


def state_file(session_id: str, root: str) -> str:
    key = hashlib.sha256(f"{session_id}\0{root}".encode()).hexdigest()[:16]
    return os.path.join(state_dir(), f"verify-{key}.json")


def _is_number(value) -> bool:
    # bool is a subclass of int; a JSON true/false must not pass as a timestamp.
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def load_state(path: str) -> dict:
    empty = {"verifications": [], "last_updated": time.time()}
    try:
        with open(path) as handle:
            state = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return empty
    if not isinstance(state, dict):
        return empty
    verifications = state.get("verifications")
    last_updated = state.get("last_updated")
    if not isinstance(verifications, list) or not _is_number(last_updated):
        return empty
    for entry in verifications:
        # S3: validate value TYPES, not just key presence — a string `time`
        # would crash the `now - time` arithmetic in the gate.
        if not isinstance(entry, dict):
            return empty
        if not isinstance(entry.get("category"), str) or not _is_number(entry.get("time")):
            return empty
    if time.time() - last_updated > STALE_SECONDS:
        return empty
    return state


def save_state(path: str, state: dict) -> None:
    state["last_updated"] = time.time()
    tmp = f"{path}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(state, handle)
    os.replace(tmp, path)


def categories(command: str) -> list:
    found = []
    if TEST_RE.search(command):
        found.append("test")
    if LINT_RE.search(command):
        found.append("lint")
    return found


def has_project(root: str) -> bool:
    if any(os.path.exists(os.path.join(root, marker)) for marker in PROJECT_MARKERS):
        return True
    return any(glob.glob(os.path.join(root, pattern)) for pattern in GLOB_MARKERS)


def should_record(command: str) -> bool:
    # Reject shell metacharacters that could chain or mask a failure. `&&` is
    # the only permitted separator, so strip it before the bare-`&` check.
    if "\n" in command:
        return False
    if any(token in command for token in (";", "|", "$(", "`")):
        return False
    if "&" in command.replace("&&", ""):
        return False
    segments = [segment.strip() for segment in command.split("&&")]
    for segment in segments:
        if not segment:
            return False
        # No inline-`cd` allowance (R3-3): `cd other-repo && npm test` runs tests
        # elsewhere but would authorize THIS repo. A real dir change is a separate
        # tool call, so the next event already carries the correct cwd.
        if not APPROVED_RE.match(segment):
            return False
    return bool(categories(command))


def write_verification(command: str, path: str) -> None:
    state = load_state(path)
    now = time.time()
    for category in categories(command):
        state["verifications"].append({"category": category, "time": now})
    state["verifications"] = state["verifications"][-20:]
    save_state(path, state)


def deny(reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))


def gate(command: str, path: str, root: str) -> None:
    if not has_project(root):
        return  # docs-only repo, nothing to verify
    state = load_state(path)
    now = time.time()
    recent = [v for v in state["verifications"] if now - v.get("time", 0) < RECENT_SECONDS]
    has_test = any(v.get("category") == "test" for v in recent)
    has_lint = any(v.get("category") == "lint" for v in recent)

    missing = []
    if not has_test:
        missing.append("tests (npm test, pytest, cargo test, etc.)")
    if not has_lint:
        missing.append("linting/typecheck (npm run lint, tsc --noEmit, mypy, etc.)")
    if not missing:
        return

    msg = "PRE-COMPLETION CHECKLIST FAILED\n\n"
    msg += "You are about to commit/push but have NOT run:\n"
    for item in missing:
        msg += f"  - {item}\n"
    msg += "\nRun the missing checks first, then retry the commit. "
    msg += "Golden Principle #7: Verify Before Claiming Done.\n"
    msg += "If tests/linting don't apply to this repo, explain why to the user."
    deny(msg)


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    if event.get("tool_name") != "Bash":
        return
    command = event.get("tool_input", {}).get("command", "")
    if not command:
        return

    session_id = event.get("session_id") or "default"
    cwd = event.get("cwd") or os.getcwd()
    root = project_root(cwd)
    hook_event = event.get("hook_event_name", "")

    if hook_event == "PostToolUse":
        if should_record(command):
            try:
                write_verification(command, state_file(session_id, root))
            except (StateDirError, OSError):
                pass  # cannot record safely; the gate will fail closed
    elif COMMIT_PATTERN.search(command):  # PreToolUse (default) — gate only
        # R4-4: catch BOTH the security refusal and any I/O error, and emit a
        # deny DECISION (not a bare exit 1 — a PreToolUse exit 1 does NOT block).
        try:
            path = state_file(session_id, root)
        except (StateDirError, OSError) as exc:
            if has_project(root):   # only block a real project, not docs-only
                deny(
                    "PRE-COMPLETION CHECKLIST: cannot verify.\n"
                    f"The harness state directory is unusable (insecure or unwritable): {exc}\n"
                    "Refusing to certify verification (fail-closed). Fix that "
                    "directory's ownership/permissions, then retry."
                )
            return
        gate(command, path, root)


if __name__ == "__main__":
    main()
```

Notes: `os.getuid()`/`os.lstat` are POSIX (the kit targets macOS+Linux). The state key's directory component is the canonical **project root** (R3-3, ordering hardened by R4-1): a single read-only `git -C "$cwd" rev-parse --show-toplevel` on the **event `cwd` is resolved first**, and `CLAUDE_PROJECT_DIR` is consulted only as a fallback — and even then only when `cwd` is inside it — so a stale or exported `CLAUDE_PROJECT_DIR` from another repo cannot key this repo's state to the wrong project (the cross-repo authorization escape R4-1 closes). This is why `subprocess` is now imported — a deliberate, bounded reversal of round-2's no-subprocess stance, needed so `cd other-repo && npm test` (already rejected by `should_record`) and a commit issued from a subdirectory both resolve to the same repo identity. No bare `except` (code-style); specific exceptions only. `PostToolUseFailure` is intentionally not handled, so a failed command records nothing.

- [ ] **Step 4: Verify syntax + shellcheck.**

Run: `python3 -m py_compile hooks/pre-completion-checklist.py`
Expected: no output, exit 0.
Run: `shellcheck hooks/pre-commit-verify.sh`
Expected: no output, exit 0.
Run: `grep -rn 'Golden Principle #8' hooks/`
Expected: no output.
Run: `grep -n 'CLAUDE_SESSION_ID' hooks/pre-completion-checklist.py`
Expected: no output (no env session id anywhere).
Run: `grep -n 'tool_response' hooks/pre-completion-checklist.py`
Expected: exactly one match, in the module docstring (the line "…no exit-code/tool_response inspection is needed…") — the string must NOT appear in any code line (the docstring documents the design; the logic never inspects `tool_response`).
Run: `grep -c 'os.environ.get("CLAUDE_PROJECT_DIR")' hooks/pre-completion-checklist.py`
Expected: `1` (the single CODE reference is the **bounded fallback** in `project_root()`; the git top-level of the event `cwd` is resolved **first** — R4-1. The bare string `CLAUDE_PROJECT_DIR` also appears in the docstring and two comments, so a bare `grep -c 'CLAUDE_PROJECT_DIR'` returns 4 — that is expected and fine.)

Behavioral verification (PostToolUse-only recording, anchored-validation negatives, session+project-root scoping, deny/allow, future+stale stamp) is covered by `tests/smoke.sh` (Task 11a).

- [ ] **Step 5: Commit.**

```bash
git add hooks/pre-commit-verify.sh hooks/pre-completion-checklist.py
git commit -m "fix: redesign verification hooks — PostToolUse-only record with anchored validation, cwd-scoped 0600 state; stamp future/seconds guard; GP #7"
```

---

### Task 4: Land `hooks/stop-verify.sh` — two loop guards, project-dir cd, cheap guards

**Findings:** 14; Codex 2, 8, 9; Codex R2 (R2, S5, S6)

**Files:**
- Create: `hooks/stop-verify.sh`

**Model:** sonnet
**Advisory:** None

- [ ] **Step 1: Write the file** so it reads EXACTLY (bash 3.2-safe — no `mapfile`/associative arrays):

```bash
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
```

Design: (a) exit **2** + all messages on **stderr**; (b) failing output captured and tailed to stderr; (c) **two loop guards** — structural `stop_hook_active` parse (Codex 2) AND a per-(session, project) block counter (R2-R2, hardened in R3-7) that warn-allows after ≥2 blocks in 10 min, reset on green; (d) `cd "${CLAUDE_PROJECT_DIR:-.}"` (Codex 8); (e) command existence guards — npm scripts read via **python3 json** (S5), typecheck only via `./node_modules/.bin/tsc` if executable (S6, replaces deprecated `npx --no-install`), `python3 -m pytest`; (f) header WARNING that the hook executes repo commands. **R3-7:** the counter dir is the same **lstat-validated** 0700 dir the checklist uses (a blind `mkdir -p`/`chmod` could follow a pre-planted symlink); the counter key is `sha256(session_id + project_root)` so a red loop in repo A cannot warn-allow a stop in repo B; counter lines are numeric-validated before arithmetic and expired entries are pruned on each write.

- [ ] **Step 2: Make executable + shellcheck.**

Run: `chmod +x hooks/stop-verify.sh`
Run: `shellcheck hooks/stop-verify.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Smoke all three policy paths locally** (fixture whose test fails; a fresh session per case so the counter is clean).

Run: `d=$(mktemp -d); printf '{"scripts":{"test":"exit 1"}}\n' > "$d/package.json"; s="sess-$$"; ( cd "$d" && CLAUDE_PROJECT_DIR="$d" printf '{"stop_hook_active":false,"session_id":"'"$s"'"}' | CLAUDE_PROJECT_DIR="$d" bash /Users/cevin/src/harness-kit/hooks/stop-verify.sh ); echo "exit=$?"`
Expected: `BLOCK:` on stderr, `exit=2`. (Behavioral coverage incl. the counter guard is in `tests/smoke.sh`, Task 11a.)

- [ ] **Step 4: Commit.**

```bash
git add hooks/stop-verify.sh
git commit -m "feat: land stop-verify Stop hook (two loop guards, project-dir cd, json script detection)"
```

---

### Task 5: Land `hooks/settings-snippet.json` in the real Claude Code schema

**Findings:** 15; Codex 1d, 8

**Files:**
- Create: `hooks/settings-snippet.json`

**Model:** haiku
**Advisory:** None

- [ ] **Step 1: Write the file** using the nested matcher-group schema. Three groups: `Stop` (no `matcher` — ignored for Stop, Codex 8), `PreToolUse` (gate), and `PostToolUse` (record) — the last two both invoke the same script, which branches on `hook_event_name`. Commands use `${CLAUDE_PROJECT_DIR}` so they resolve from any cwd (Codex 8):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/stop-verify.sh\"" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "python3 \"${CLAUDE_PROJECT_DIR}/.claude/hooks/pre-completion-checklist.py\"" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "python3 \"${CLAUDE_PROJECT_DIR}/.claude/hooks/pre-completion-checklist.py\"" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON + group presence.**

Run: `python3 -m json.tool hooks/settings-snippet.json`
Expected: pretty-printed JSON, exit 0.
Run: `python3 -c "import json;h=json.load(open('hooks/settings-snippet.json'))['hooks'];print(sorted(h))"`
Expected: `['PostToolUse', 'PreToolUse', 'Stop']`.

- [ ] **Step 3: Commit.**

```bash
git add hooks/settings-snippet.json
git commit -m "feat: add Claude Code settings snippet (Stop + PreToolUse gate + PostToolUse record)"
```

---

### Task 6: Land the reference-doc templates

**Findings:** 17, 18, 19, 22

**Files:**
- Create: `docs/decision-record-template.md` (as-is copy)
- Create: `docs/eval-template.md` (as-is copy)
- Create: `docs/escape-hatch-audit.md` (copy + one-line provenance fix)
- Create: `docs/context-inheritance-audit.md` (as-is copy)

**Model:** haiku
**Advisory:** None

- [ ] **Step 1: Copy four files verbatim from the vault** into `docs/`:
  - `decision-record-template.md`, `eval-template.md`, `escape-hatch-audit.md`, `context-inheritance-audit.md`.

- [ ] **Step 2: Fix the dangling reference in `docs/escape-hatch-audit.md`** (finding 19). The file cites book/vault material that is not shipped in the repo. Replace line 6:

Old:
```markdown
> See also: harness-debugging-case-studies.md for real-world examples of each pattern.
```
New:
```markdown
> See also: The Harness Engineering Playbook, Ch. 18b (When the Harness Breaks) for real-world examples of each pattern.
```

- [ ] **Step 3: Verify no other dangling repo-relative references** in the four new docs.

Run: `grep -rn 'harness-debugging-case-studies' docs/`
Expected: no output.

- [ ] **Step 4: Commit.**

```bash
git add docs/decision-record-template.md docs/eval-template.md docs/escape-hatch-audit.md docs/context-inheritance-audit.md
git commit -m "docs: land decision-record, eval, escape-hatch, context-inheritance templates"
```

---

### Task 7: Land `skills/review.md`

**Findings:** 16

**Files:**
- Create: `skills/review.md` (as-is copy from vault)

**Model:** haiku
**Advisory:** None

- [ ] **Step 1: Copy `skills/review.md` verbatim** from the vault into `skills/review.md`. The vault version is good as-is; do not restructure it. This is the single source of the skill body — `install.sh` (T9 Step 9) generates the Claude Code `.claude/skills/review/SKILL.md` by prepending YAML frontmatter to this file at install time (Codex 11), so there is no second copy to maintain. Other agents reference `skills/review.md` directly.

- [ ] **Step 2: Verify.**

Run: `test -f skills/review.md && head -1 skills/review.md`
Expected: `# /review — Structural Code Audit`

- [ ] **Step 3: Commit.**

```bash
git add skills/review.md
git commit -m "feat: land structural code-review skill"
```

---

### Task 8: Merge AGENTS.md Code Style sections; add anti-rationalization + orchestration rules

**Findings:** 8, 21

**Files:**
- Modify: `AGENTS.md`

**Model:** sonnet
**Advisory:** None

Constraint: keep `AGENTS.md` under 100 lines (kit GP #4, Progressive Disclosure — root files are maps).

- [ ] **Step 1: Merge the two `## Code Style` sections into one** (finding 8). The template currently has an inline-rules section (lines 22-27) and a pointer section (lines 59-60). Replace the inline section (lines 22-27) with the merged block, and DELETE the standalone pointer section (lines 59-60).

Merged block (replaces the first `## Code Style` section):
```markdown
## Code Style
<!-- Replace with project-specific conventions -->
- NEVER use `any` in TypeScript — use `unknown` if the type is genuinely unknown
- NEVER swallow errors with empty catch blocks — at minimum, log them
- NEVER use default exports — use named exports only
- Comments explain WHY, not WHAT

Read docs/code-style.md when: writing Python, TypeScript, Angular, JavaScript, HTML, or SCSS.
```

Delete these now-duplicate lines (currently 59-60):
```markdown
## Code Style
Read docs/code-style.md when: writing Python, TypeScript, Angular, JavaScript, HTML, or SCSS.
```

- [ ] **Step 2: Add the two anti-rationalization bullets to `## Never Do`** (finding 21), after the last existing bullet (`- NEVER retry the same failed approach more than 3 times — escalate instead`). Bullet 1 is copied from the vault; bullet 2 is generalized from the vault's CC-specific wording to fit this universal, tool-agnostic template (the format-vs-function lesson is preserved):

```markdown
- NEVER construct a reason why a particular edit "doesn't count" as a code change.
  Updating test expectations, changing string literals, fixing typos, renaming variables —
  these are ALL code changes. If you are building a rationale for why a specific edit is
  exempt from a rule, that rationale is the signal to follow the rule.
- NEVER edit agent configuration files directly just because they use a `.md` extension
  (skill definitions, prompt templates, workflow specs). They are configuration, not
  documentation — route changes through your normal process.
```

- [ ] **Step 3: Add an `## Orchestration Rules` section** (finding 21), placed after `## Never Do` and before `## Golden Principles`. (Step 1 already moved the merged `## Code Style` above `## Never Do` and deleted the trailing pointer section, so `## Golden Principles` is the next section after `## Never Do`.) Copied from the vault, kept clearly conditional:

```markdown
## Orchestration Rules
<!-- Applies only if this project uses agent teams or multi-agent workflows. Delete this section if it does not. -->

If this project uses agent teams or multi-agent workflows:

1. **Dispatch first, self-execute second.** When you have both delegatable work (agent tasks)
   and self-executable work (memory saves, doc writes, context reads), dispatch agents FIRST,
   then do your own tasks while agents run. Agent work takes longer — start it immediately.

2. **One file, one audience.** This AGENTS.md is for the orchestrator. Worker-specific
   instructions belong in reference files that workers load on demand. If you find yourself
   writing instructions here that only apply to implementers or reviewers, move them to
   the appropriate reference file.

3. **Context inheritance.** Every agent that touches code receives docs/code-style.md.
   Every agent that makes decisions receives docs/golden-principles.md. Every agent that
   plans receives team memory. If you add a new reference file, update the dispatch
   instructions for every agent that needs it.
```

- [ ] **Step 4: Verify structure and length.**

Run: `grep -c '^## Code Style' AGENTS.md`
Expected: `1` (sections merged).
Run: `wc -l AGENTS.md`
Expected: under 100 (kit GP #4).

- [ ] **Step 5: Commit.**

```bash
git add AGENTS.md
git commit -m "docs: merge duplicate Code Style sections; add anti-rationalization and orchestration rules"
```

---

### Task 9: Update `install.sh` — coexistence, hook chaining, doc parity, bundle install

**Findings:** 5, 6, 7, 9, 23 (installer portion); Codex 3, 4, 11

**Files:**
- Modify: `install.sh`

**Model:** sonnet (grew substantially — worktree/hooksPath handling, hook chaining, SKILL.md generation; still sonnet, note increased size)
**Advisory:** None
**Depends on:** Tasks 4, 5, 6, 7 (bundle files must exist to be copied).

**Side-effects:** installs files into consumer repos (docs, skills, `.claude/hooks/`, `.claude/skills/`), and in the raw-hook fallback writes git hooks under `git rev-parse --git-path hooks`. It NEVER auto-edits `settings.json` and NEVER runs `pre-commit install` against a foreign config.

- [ ] **Step 1: Gate on the git top-level, not `.git` presence** (Codex 3a — worktrees have a `.git` FILE). Replace (currently lines 24-28):

Old:
```bash
# Check we're in a git repo
if [ ! -d .git ]; then
    echo "ERROR: Not a git repository. Run from a project root."
    exit 1
fi
```
New:
```bash
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
```

- [ ] **Step 2: Copy `docs/harness-philosophy.md` and `docs/code-style.md`** (findings 5, 6). After the golden-principles copy block, add:

```bash
# 2b. Human-reference + code-style docs (README's "What It Creates" lists these)
for doc in harness-philosophy.md code-style.md; do
    if [ -f "docs/$doc" ]; then
        echo "⟳ docs/$doc already exists — skipping"
    else
        cp "$HARNESS_KIT/docs/$doc" "docs/$doc"
        echo "✓ Created docs/$doc"
    fi
done
```

- [ ] **Step 3: Make the `.harness/hooks/*` copies skip-if-exists** (Codex 3e). Replace the current unconditional copy block (currently lines 48-53):

Old:
```bash
mkdir -p .harness/hooks
cp "$HARNESS_KIT/hooks/no-mocks.sh" .harness/hooks/no-mocks.sh
cp "$HARNESS_KIT/hooks/pre-commit-verify.sh" .harness/hooks/pre-commit-verify.sh
cp "$HARNESS_KIT/hooks/post-commit-cleanup.sh" .harness/hooks/post-commit-cleanup.sh
chmod +x .harness/hooks/*.sh
echo "✓ Installed git hook scripts to .harness/hooks/"
```
New:
```bash
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
```

- [ ] **Step 4: Track whether `.pre-commit-config.yaml` pre-existed, and never claim false success** (Codex 3c; R3-6; **R4-3 conservative rewrite**). Replace the config-copy block (currently lines 55-61):

Old:
```bash
# 4. Pre-commit config
if [ -f .pre-commit-config.yaml ]; then
    echo "⟳ .pre-commit-config.yaml already exists — merging manually required"
else
    cp "$HARNESS_KIT/.pre-commit-config.yaml" .pre-commit-config.yaml
    echo "✓ Created .pre-commit-config.yaml"
fi
```
New:
```bash
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
```

- [ ] **Step 5: Rewrite the hook-install decision — chain existing hooks, honor `core.hooksPath`, warn on foreign config** (Codex 3b, 3c, 4). Replace the whole `if command -v pre-commit …` block (currently lines 63-89):

Old:
```bash
# Install pre-commit hooks if pre-commit is available
if command -v pre-commit &> /dev/null; then
    pre-commit install
    pre-commit install --hook-type post-commit
    echo "✓ Installed pre-commit hooks"
else
    # Fallback: install hooks directly via git
    echo "pre-commit not found — installing hooks directly via git"

    # Pre-commit hook
    cat > .git/hooks/pre-commit << 'HOOK'
#!/usr/bin/env bash
# Harness pre-commit: no-mocks + verification check
.harness/hooks/no-mocks.sh && .harness/hooks/pre-commit-verify.sh
HOOK
    chmod +x .git/hooks/pre-commit

    # Post-commit hook
    cat > .git/hooks/post-commit << 'HOOK'
#!/usr/bin/env bash
# Harness post-commit: clean up verification stamp
.harness/hooks/post-commit-cleanup.sh
HOOK
    chmod +x .git/hooks/post-commit

    echo "✓ Installed git hooks directly (no pre-commit framework)"
fi
```
New:
```bash
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
```

Chaining (Codex 4): a foreign hook is renamed to `<hook>.harness-preserved` (installer refuses if that name already exists — no overwrite), and our wrapper (marked `# harness-kit hook`) invokes it FIRST, propagating a non-zero exit for pre-commit (`|| exit $?`) and ignoring failure for post-commit (`|| true`). Ownership is the exact marker line, so re-runs skip our own hooks (idempotent).

**R3-2 (core.hooksPath / symlink escape — hardened).** `install_raw_git_hooks` resolves the hooks directory (which `git rev-parse --git-path hooks` derives from `core.hooksPath`) to a canonical absolute path with `_realpath` (Python `os.path.realpath`, which does **not** require the path to exist) **before creating anything** — so a refused external path is never `mkdir`-ed as a side effect. Containment is allowed under the canonicalized top-level OR `--absolute-git-dir` OR **`--git-common-dir`**; the common-dir clause exists because a **linked worktree** places its shared hooks under the common dir, which is under neither of the other two (verified against a real worktree, round 3) — though since R5-1 a linked worktree is refused before `install_raw_git_hooks` is ever reached, so in practice the clause is only exercised from the primary worktree (kept as defense-in-depth). Symlink and preserved-name collisions are checked by `preflight_raw_hook` for **both** hooks before either is written, so a refusal never leaves a half-installed state. Refusals set `INACTIVE_REASON=refused`; in explicit `direct` mode the caller treats a refusal as **fatal** (`|| exit 1`), while the `auto` fallback leaves hooks inactive and lets the banner report it.

**R4-2 / R5-2 (no false success; both hooks are one transaction).** Because `install_raw_git_hooks` is invoked left of `||`, `set -e` is suspended inside it, so every mutating step is checked explicitly: `mkdir -p … || return 1`, and the whole two-hook write is a **transaction (R5-2)**. Both `pre-commit` and `post-commit` (and each one's `.harness-preserved` sibling) are snapshotted with content+mode into a temp dir *before any mutation*; `_apply_raw_hook` then writes both. If **either** apply step fails — the reachable case is a marker-owned but non-executable `post-commit` after `pre-commit` is already written — `_restore_hook` restores **both** hooks to their exact snapshots with **checked** rollback operations that report loudly (`ERROR: rollback failed …`) if a rollback op itself fails, so we can never leave `pre-commit` active while the function returns failure and the banner says inactive. A marker-owned non-executable hook (a prior half-install) is repaired with `chmod +x` **inside** the transaction, so it too is rolled back cleanly if the other hook later fails. Ownership is matched with `grep -Fxq '# harness-kit hook'` (fixed-string, whole-line) so a substring in an unrelated hook's comment can't be mistaken for ours.

**R5 (deterministic installer paths).** `HARNESS_KIT_HOOK_MODE` (validated to `auto|direct|precommit` in Step 1) selects the branch: `direct` always installs raw git hooks even when the framework is present; `precommit` requires the framework and hard-errors if it is missing **or if the config is foreign/partial** (R3-6 — it would otherwise install against the user's config); unset/`auto` keeps the historical auto-detect. The smoke test drives `precommit` and `direct` explicitly so assertions never depend on what happens to be installed on the runner.

**R6 (truthful success banner).** Every path that actually wires hooks sets `HOOKS_ACTIVE=true`; the foreign-config branch (`INACTIVE_REASON=foreign`), the R3-2 refusals (`INACTIVE_REASON=refused`), and the **linked-worktree refusal** (`INACTIVE_REASON=worktree`, R5-1) leave it `false`. Step 12 keys the closing banner off `HOOKS_ACTIVE` and picks the follow-up text off `INACTIVE_REASON` (`worktree` → "re-run from the primary worktree"; `refused` → manual-wire; `foreign` → merge-config), so a containment or worktree refusal never prints the irrelevant "merge .pre-commit-config.yaml" instructions.

- [ ] **Step 6: Fix the Cursor wrapper to test the FILE, not the directory** (Codex 3d). Replace (currently lines 116-131):

Old:
```bash
# 7. Thin Cursor rules wrapper
if [ ! -d .cursor/rules ]; then
    mkdir -p .cursor/rules
    cat > .cursor/rules/harness.md << 'EOF'
```
New:
```bash
# 7. Thin Cursor rules wrapper
mkdir -p .cursor/rules
if [ -f .cursor/rules/harness.md ]; then
    echo "⟳ .cursor/rules/harness.md already exists — skipping"
else
    cat > .cursor/rules/harness.md << 'EOF'
```
(The heredoc body is unchanged; keep the existing `EOF` and the trailing `echo "✓ Created .cursor/rules/harness.md (thin wrapper)"` inside the new `else` branch, closing with `fi`.)

- [ ] **Step 7: Replace the generated `CLAUDE.md` wrapper with tool-agnostic guidance** (finding 7). Replace the `## Claude-Specific` lines in the heredoc:

Old:
```bash
## Claude-Specific
- Use subagent-driven development for implementation plans
- Store architectural decisions in ContextKeep
- Use codesight-mcp for code navigation instead of reading full files
```
New:
```bash
## Claude-Specific
- Use subagent-driven development for implementation plans
- Capture significant architectural decisions as decision records (see docs/decision-record-template.md)
- If you use a code-navigation MCP server, prefer it over reading whole files
```

- [ ] **Step 8: Install reference-doc templates + review skill** (finding 23). Add (after the Cursor block):

```bash
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
```

- [ ] **Step 9: Generate the Claude Code SKILL.md from the repo skill** (Codex 11 — a real CC skill, no second copy to maintain). Add:

```bash
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
```

- [ ] **Step 10: Install the Claude Code dynamic hooks** (finding 23; skip-if-exists). Add:

```bash
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
```

- [ ] **Step 11: Add the manual settings-merge step to the closing "Next steps" block.** Add:

```bash
echo "Claude Code users — enable the dynamic hooks:"
echo "  Merge .claude/hooks/settings-snippet.json into .claude/settings.json"
echo "  (Stop: verify before finishing; PreToolUse: commit gate; PostToolUse: record verification)"
echo ""
```

- [ ] **Step 12: Replace the closing success banner with a truthful, `HOOKS_ACTIVE`-keyed block** (R6). The real `install.sh` closing banner (verified against the file — **lines 133-136**) is the `=====`-framed block below; it unconditionally prints "Harness installed successfully." even when the foreign-config branch or an R3-2 refusal left hooks unwired. Replace exactly that block (leave the later `echo "Next steps:"` lines, which Step 11 edits):

Old:
```bash
echo ""
echo "========================================="
echo "Harness installed successfully."
echo "========================================="
```
New:
```bash
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
```

Single source of truth for the final banner: no path prints "installed successfully" unless `HOOKS_ACTIVE=true`, and the follow-up text is chosen off `INACTIVE_REASON` so a containment refusal never prints the irrelevant "merge .pre-commit-config.yaml" line (R3-6). The smoke foreign-config scenario (Task 11a) asserts the `NOT active` wording appears and `installed successfully` does not.

- [ ] **Step 13: Verify install.sh end-to-end + shellcheck.**

Run: `shellcheck install.sh`
Expected: no output, exit 0.
Run: (throwaway) `d=$(mktemp -d); (cd "$d" && git init -q && bash /Users/cevin/src/harness-kit/install.sh) ; ls "$d/docs" "$d/skills" "$d/.claude/hooks" "$d/.claude/skills/review"`
Expected: `docs/` has golden-principles, harness-philosophy, code-style, and the four templates; `skills/review.md`; `.claude/hooks/` has the three files; `.claude/skills/review/SKILL.md` exists.
Run: `head -1 "$d/.claude/skills/review/SKILL.md"`
Expected: `---` (valid skill frontmatter).

- [ ] **Step 14: Commit.**

```bash
git add install.sh
git commit -m "feat: installer coexistence (git-toplevel gate, core.hooksPath, hook chaining), bundle + Claude skill install; tool-agnostic CLAUDE.md"
```

---

### Task 10: Update README — install/uninstall/expiry docs, 18-count, new files, 4-layer architecture, CI badge

**Findings:** 10, 20 (README counts), 23 (README portion)

**Files:**
- Modify: `README.md`

**Model:** sonnet
**Advisory:** None
**Depends on:** Tasks 2, 4-7, 9 (files referenced must exist) and Task 11b (CI workflow name for the badge).

**IMPLEMENTER NOTE — zero-width spaces are a plan-rendering artifact, do NOT ship them.** The "New:" blocks in Step 2 and Step 5 contain U+200B zero-width-space characters immediately before nested ` ``` ` fence delimiters (they stop this plan's own outer fence from breaking). Strip every U+200B when writing the literal `README.md` content — a non-whitespace character before backticks violates CommonMark's fence-opening rule and would silently break GitHub's rendering. Verify after writing: `python3 -c "import sys; sys.exit(1 if '\u200b' in open('README.md').read() else 0)"` — expected exit 0.

- [ ] **Step 1: Add a CI badge** (finding 24) directly under the `# Harness Kit` title:

```markdown
# Harness Kit

[![CI](https://github.com/cmillstead/harness-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/cmillstead/harness-kit/actions/workflows/ci.yml)
```

- [ ] **Step 2: Add `git clone` install instructions** (finding 10). Replace the `## Install` block:

Old:
```markdown
## Install

​```bash
cd /path/to/your/project
~/src/harness-kit/install.sh
​```
```
New:
```markdown
## Install

​```bash
# 1. Clone the kit somewhere stable
git clone https://github.com/cmillstead/harness-kit.git ~/src/harness-kit

# 2. From your project root, run the installer
cd /path/to/your/project
~/src/harness-kit/install.sh
​```
```

- [ ] **Step 3: Update both "16" counts to "18"** (finding 20). Line 21 table row and line 66 prose:

Old (table): `| `docs/golden-principles.md` | 16 operational rules for agents | All |`
New: `| `docs/golden-principles.md` | 18 operational rules for agents | All |`

Old (prose): `16 operational rules that change agent behavior. Not philosophy — actionable tiebreakers. Examples: "Real over mocks," "Bounded iteration," "Consolidate before adding," "Naming is architecture."`
New: `18 operational rules that change agent behavior. Not philosophy — actionable tiebreakers. Examples: "Real over mocks," "Bounded iteration," "Consolidate before adding," "Define exceptions by purpose, not format."`

- [ ] **Step 4: Add new-file rows to the "What It Creates" table** (finding 23). These are artifacts `install.sh` now creates. Append after the `.pre-commit-config.yaml` row:

```markdown
| `skills/review.md` | Structural code-audit skill | All |
| `docs/decision-record-template.md` | Capture the "why" behind decisions | — |
| `docs/eval-template.md` | Domain-specific eval criteria (any team) | — |
| `docs/escape-hatch-audit.md` | 10-step diagnostic for harness failure patterns | — |
| `docs/context-inheritance-audit.md` | Matrix audit for multi-agent context wiring | — |
| `.claude/hooks/stop-verify.sh` | Stop hook: tests/lint/typecheck before finishing | Claude Code |
| `.claude/hooks/pre-completion-checklist.py` | PreToolUse hook: verify before commit/push | Claude Code |
| `.claude/hooks/settings-snippet.json` | Settings to wire up the Claude Code hooks | Claude Code |
```

- [ ] **Step 5: Adopt the 4-layer architecture diagram** (finding 23). Replace the current 3-layer diagram (lines 30-37) with:

```markdown
​```
Layer 1: Universal (git hooks + AGENTS.md + golden principles)
  ↓ works with any agent
Layer 2: Tool-specific thin wrappers (CLAUDE.md, .cursor/rules/)
  ↓ points back to Layer 1
Layer 3: Dynamic harness (agent hooks + skills)
  ↓ event-driven control + modular instructions
Layer 4: Tool-specific features (Claude hooks, Cursor hooks)
  ↓ cannot be abstracted
​```

Layer 3 is the dynamic layer — Stop/PreToolUse hooks and skills that act at runtime, from Playbook Ch. 12b.
```

- [ ] **Step 6: Document the stamp's 30-minute expiry** (finding 10) in the Verification Workflow block:

Old:
```markdown
# Stamp auto-deleted after commit — must re-verify next time
```
New:
```markdown
# Stamp auto-deleted after commit — must re-verify next time.
# The stamp also expires 30 minutes after creation; a stale stamp is
# rejected and deleted, so re-run tests/lint if you paused mid-change.
```

- [ ] **Step 7: Add provenance lines + new "What's Inside" entries** (finding 23). In "What's Inside", add short subsections with Playbook provenance:

```markdown
### Review Skill
A "paranoid senior engineer" audit skill: find bugs, not improvements. Claude Code gets it automatically — the installer generates `.claude/skills/review/SKILL.md` (frontmatter + body). Other agents reference `skills/review.md` directly. See: Playbook Ch. 12b.

### Reference-Doc Templates
- `docs/decision-record-template.md` — capture the *why* behind decisions (Playbook Ch. 3)
- `docs/eval-template.md` — domain-specific eval criteria for any team (Playbook Ch. 7)
- `docs/escape-hatch-audit.md` — diagnose and close harness escape hatches (Playbook Ch. 18b)
- `docs/context-inheritance-audit.md` — audit shared-context wiring across agents (Playbook Ch. 3)

### Claude Code Hooks (optional)
**Enabling these hooks runs repository-defined commands (npm test/lint, pytest, cargo) — only enable them in repos you trust.**
- `.claude/hooks/stop-verify.sh` — Stop hook; runs tests/lint/typecheck before the agent finishes. First blocked stop exits 2; a retried stop that is still red warns and allows (bounded — no loop). Playbook Ch. 12b.
- `.claude/hooks/pre-completion-checklist.py` — PreToolUse gate + PostToolUse record: blocks a commit/push unless this session actually ran tests AND lint. Verifications are recorded *after* a command runs, so a failing test never counts.
- Wire them up by merging `.claude/hooks/settings-snippet.json` into `.claude/settings.json` (it uses `${CLAUDE_PROJECT_DIR}` paths and registers Stop, PreToolUse, and PostToolUse).
```

- [ ] **Step 8: Add a MANUAL "Uninstall" checklist** (finding 10; Codex 5; round-2 R6 — **supersedes the round-1 uninstall script**) before "## Customization". A copy-paste `rm -f … \`-list is itself a footgun: some of these paths (`AGENTS.md`, `CLAUDE.md`, `.pre-commit-config.yaml`, an edited hook) may hold the user's own edits, and a single blanket command deletes them with no review step. Ship a **review-before-removal checklist** instead — the user inspects each item and removes it deliberately. Do NOT ship a runnable teardown script.

```markdown
## Uninstall

The installer is mostly additive, but not purely: besides copying files it appends a `.harness-verified` line to your `.gitignore`, and when it wires git hooks it may rename a pre-existing hook to `<hook>.harness-preserved` (chaining it) and/or register hooks through the pre-commit framework. There is deliberately **no teardown script** — some of these files (`AGENTS.md`, `CLAUDE.md`, `.cursor/rules/harness.md`, a `.gitignore` you already maintained, and any hook you edited) may contain your own changes, and a blanket `rm` would take them with it. Work through this checklist, reviewing each item before you delete it. `git status` / `git stash` first if you want a safety net.

**1. Harness-owned files — safe to delete if you never edited them** (run `git diff` on any you're unsure about first):

- `docs/golden-principles.md`, `docs/harness-philosophy.md`, `docs/code-style.md`
- `docs/decision-record-template.md`, `docs/eval-template.md`, `docs/escape-hatch-audit.md`, `docs/context-inheritance-audit.md`
- `skills/review.md`
- `.claude/hooks/stop-verify.sh`, `.claude/hooks/pre-completion-checklist.py`, `.claude/hooks/settings-snippet.json`
- `.claude/skills/review/SKILL.md`
- `.harness/hooks/no-mocks.sh`, `.harness/hooks/pre-commit-verify.sh`, `.harness/hooks/post-commit-cleanup.sh`
- `.harness-verified` (a transient stamp; also drop its `.gitignore` line if you added one)

After deleting, prune the now-empty dirs: `.claude/skills/review`, `.claude/skills`, `.claude/hooks`, `.harness/hooks`, `.harness`, `skills` (leave any you also use for non-harness content).

**2. Git hooks — restore only after removing our wrapper.** Find your hooks dir with `git rev-parse --git-path hooks`. For each of `pre-commit` and `post-commit`, in this order:

- If the hook file has **no** `# harness-kit hook` marker, it is not ours — leave it, and leave any `<hook>.harness-preserved` sibling, untouched. Do NOT restore over a hook you did not install.
- If the hook file contains `# harness-kit hook`, it is ours — delete it. THEN, and only then, if a `<hook>.harness-preserved` sibling exists it is *your* original that we chained: rename it back (`mv pre-commit.harness-preserved pre-commit`).

Restoring the preserved hook only after positively identifying and removing our wrapper guarantees you never overwrite a live non-harness hook.

**3. `.pre-commit-config.yaml` — inspect before removing.** If it references `.harness/hooks/no-mocks.sh` *and* you had no pre-commit config before installing, it is the harness's copy — delete it. If you merged harness entries into a pre-existing config, remove only those entries by hand. If you enabled the pre-commit framework, also run `pre-commit uninstall && pre-commit uninstall --hook-type post-commit`.

**4. Review by hand — never auto-delete.** `AGENTS.md`, `CLAUDE.md`, and `.cursor/rules/harness.md` are meant to be customized. Open each and remove the harness sections you no longer want, keeping your own edits.
```

Rationale for the checklist form (state this in the plan, not the README): the round-1 script mixed *always-safe* deletes (generated templates) with *review-required* ones (chained hooks, possibly-merged config, user-edited docs) behind one command. Round-2 splits them by risk and puts a human decision in front of every removal, which is the correct posture for a teardown that can hit user-authored files.

- [ ] **Step 9: Note re-install behavior in "## Customization"** (Codex 3e). Add to the `.harness/hooks/` customization bullet:

Append: `To pull a fresh copy of a harness hook after editing it, delete your copy and re-run install.sh (the installer skips files that already exist).`

- [ ] **Step 10: Verify.**

Run: `grep -n '16 operational' README.md`
Expected: no output.
Run: `grep -c 'Layer 4' README.md`
Expected: `1` (4-layer diagram adopted).

- [ ] **Step 11: Commit.**

```bash
git add README.md
git commit -m "docs: add clone/safe-uninstall/expiry docs, 18-count, new-file rows, 4-layer architecture, CI badge"
```

---

### Task 11a: Smoke test (`tests/smoke.sh`)

**Findings:** 24; Codex 1, 2, 4, 6, 11, 12

**Files:**
- Create: `tests/smoke.sh`

**Model:** sonnet (grew to 40 assertions with fixtures — split from CI per the reviewer's >250-line guidance)
**Advisory:** None
**Depends on:** T3, T4, T5, T9 (exercises the final hooks + installer).

**Split rationale:** the original Task 11 combined smoke + CI; the smoke script alone is now ~520 lines / 40 assertions, so it is its own task and CI is T11b. Assertions are **deterministic by design** — hermetic git config (`GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM=/dev/null`) plus the internal `HARNESS_KIT_HOOK_MODE` seam (R5) force the install path (`direct` for the main run, `direct` inside the chaining/worktree/non-exec-marker sub-repos, auto for the foreign-config cases) so a result never depends on whether `pre-commit` happens to be on the runner. Every assertion checks exit code AND message.

**Makefile decision (finding 24, stated deliberately):** Do NOT add a `Makefile` or `make test` entrypoint. Rationale: `pre-commit-verify.sh` / `pre-completion-checklist.py` both treat `Makefile` and `Justfile` as project markers — adding one would flip harness-kit's own root from "docs-only" to "requires a `.harness-verified` stamp on every commit." Tests run via `bash tests/smoke.sh`; the repo root stays marker-free.

- [ ] **Step 1: Write `tests/smoke.sh`.** Plain bash, no bats. Installer + baseline are fatal via `run_or_die`; every assertion checks exit code AND message. 40 assertions.

```bash
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
printf 'from unittest.mock import MagicMock\n' > tests/test_sample.py
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
```

Notes: the checklist test drives **PostToolUse-shaped** record payloads (`hook_event_name` + event `cwd`, **no `tool_response`** — PostToolUse fires only on success) and a **PreToolUse-shaped** deny, with `CLAUDE_PROJECT_DIR="$WORK"` so record and gate share one project root. **R4-1** proves the project root is resolved from the *event cwd*, not a stale `CLAUDE_PROJECT_DIR`: a subdirectory commit is still gated (a), a verification in a second repo does not authorize the first (b), and the first repo's state is not consumed by a commit in the second (c). The R1 block proves `should_record` rejects `||`, a leading env-assignment, and non-anchored `echo`. **R4-4** pre-plants the per-user state dir as a symlink under a redirected `TMPDIR` and asserts the gate emits a *deny decision* (fail-closed, not a bare exit). The stop-verify fixture's `test` fails deterministically (`exit 1`): the first stop blocks (exit 2), `stop_hook_active` warn-allows (Guard 1), **blocks 1 and 2 of a fresh session each exit 2**, and the 3rd warn-allows via the (session, project) counter (Guard 2). **Chaining (R3-4)** asserts installer exit 0, preserved content+mode, wrapper marker (`grep -Fxq`), a blocked commit, and the preserved output. **Containment / R5-1** asserts a linked-worktree install is **refused** (NOT-active banner, the shared common-dir hooks dir left byte-for-byte unchanged via `snapshot`, and a subsequent primary-worktree commit unaffected), and that an external `core.hooksPath` is refused with the external dir **recursively snapshot-verified** unchanged (content+mode, catching truncation/chmod/new files). **R5-2** asserts a marker-owned but non-executable post-commit (the reachable partial-install trigger) is repaired in-transaction so both hooks end up active and executable. **R6** + **R4-3** assert a foreign config, and a near-miss config that mentions all three hook paths at the wrong stage, are both treated as foreign (byte-identity) with hooks inactive. Hermeticity comes from `GIT_CONFIG_GLOBAL=/dev/null` + `GIT_CONFIG_SYSTEM=/dev/null` (R3-1 — the old `core.hooksPath` pin would make pre-commit refuse to install). The idempotency snapshot is pure Python stdlib and **includes `.git/hooks`** while pruning only volatile git internals (R3-4); the same `snapshot` helper takes an optional dir argument so the containment checks reuse it. `touch -t CCYYMMDDhhmm`, `os.walk`/`os.stat`, and `cmp` all behave identically on BSD (macOS) and GNU. **40 assertions** (the R1 line runs 3× in a loop).

- [ ] **Step 2: Make executable + shellcheck.**

Run: `chmod +x tests/smoke.sh`
Run: `shellcheck tests/smoke.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Run the smoke test locally.**

Run: `bash tests/smoke.sh`
Expected: final line `40 passed, 0 failed`, exit 0.

- [ ] **Step 4: Commit.**

```bash
git add tests/smoke.sh
git commit -m "test: add smoke test for installer, git hooks, Claude hooks, and chaining"
```

### Task 11b: CI workflow (`.github/workflows/ci.yml`)

**Findings:** 24; Codex 6

**Files:**
- Create: `.github/workflows/ci.yml`

**Model:** haiku (small YAML, complete spec)
**Advisory:** None
**Depends on:** T11a (runs `tests/smoke.sh`).

**Cross-OS choice (Codex 6, stated):** run the smoke test on `ubuntu-latest` and `macos-latest`, plus a third `ubuntu-latest` job that installs the `pre-commit` framework and forces `HARNESS_KIT_HOOK_MODE=precommit` (R5). Rationale: the macOS job validates the BSD `stat -f`/`touch -t`/`find` paths (the Darwin branch in `pre-commit-verify.sh`); the default Linux/macOS jobs exercise the raw-hook `direct` path (the smoke seam defaults to `direct`); and the precommit job proves the framework path wires the same checks — the two install paths that R5 makes deterministic are now both under CI. `shellcheck` + `py_compile` run once on Linux (OS-independent output; duplicating on macOS would need `brew install shellcheck` for no added coverage).

**S7 (workflow hardening):** the workflow declares `permissions: contents: read` (least privilege — CI only reads the repo), and every job sets `timeout-minutes` so a hung hook or install can't burn the full 6-hour default.

- [ ] **Step 1: Write `.github/workflows/ci.yml`.**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

# S7: least privilege — the workflow only needs to read the repo.
permissions:
  contents: read

jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - name: Shellcheck hooks and installer
        run: shellcheck hooks/*.sh install.sh tests/smoke.sh
      - name: Byte-compile the Python hook
        run: python3 -m py_compile hooks/pre-completion-checklist.py

  smoke-linux:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Run smoke test (raw-hook direct mode)
        run: bash tests/smoke.sh

  smoke-macos:
    runs-on: macos-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Run smoke test (raw-hook direct mode)
        run: bash tests/smoke.sh

  smoke-precommit:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Install the pre-commit framework (pinned for determinism)
        run: pipx install "pre-commit==4.6.0"
      - name: Run smoke test (pre-commit framework mode)
        env:
          HARNESS_KIT_HOOK_MODE: precommit
        run: bash tests/smoke.sh
```

`ubuntu-latest` and `macos-latest` ship `shellcheck` (Linux), `python3`, `node`/`npm`, `git`, and `pipx`. The default smoke jobs run with `HARNESS_KIT_HOOK_MODE` unset, so the smoke seam defaults to `direct` (raw-hook path). The `smoke-precommit` job installs a **pinned** pre-commit and forces `precommit`, so the same 40 assertions run against the framework install path — the chaining, worktree, non-exec-marker, and foreign-config sub-repos force their own modes internally, so they stay valid under either outer mode. The pin matters because the framework refuses to install when `core.hooksPath` is set (verified against pre-commit 4.6.0), which is exactly why the smoke test now uses `GIT_CONFIG_GLOBAL/SYSTEM=/dev/null` for hermeticity instead of pinning `core.hooksPath` (R3-1).

- [ ] **Step 2: Validate the workflow YAML.**

Run (only if PyYAML is present — not stdlib): `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
Expected: no output, exit 0. If PyYAML is unavailable, skip — the first CI run is authoritative (GitHub rejects malformed workflow YAML).

- [ ] **Step 3: Commit.**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: shellcheck + py_compile + smoke on Linux/macOS/pre-commit, least-privilege perms + timeouts"
```

---

## Traceability (24 findings)

| # | Finding | Disposition | Task |
|---|---|---|---|
| 1 | LICENSE missing | Fix | T1 |
| 2 | No `.gitignore` (`.DS_Store`, `.harness-verified`) | Fix | T1 |
| 3 | `.harness-verified` tracked in git | Fix (untrack + delete) | T1 |
| 4 | `.DS_Store` on disk | Fix (remove) | T1 |
| 5 | install.sh never copies `harness-philosophy.md` / `code-style.md` | Fix | T9 |
| 6 | Dangling `docs/code-style.md` pointer + verify others | Fix (resolved by T9 copy; verified in T9 Step 7) | T9 |
| 7 | CLAUDE.md wrapper cites private tools (ContextKeep, codesight) | Fix (tool-agnostic) | T9 |
| 8 | AGENTS.md has two `## Code Style` sections | Fix (merge) | T8 |
| 9 | install.sh fallback overwrites existing git hooks | Fix (superseded by Codex 4 — **chain**, not backup) | T9 |
| 10 | README gaps: clone, stamp expiry, uninstall | Fix (uninstall hardened per Codex 5) | T10 |
| 11 | GP "#8" citation in `pre-commit-verify.sh` + checklist.py (should be #7) | Fix (both; checklist citation baked into the T3 rewrite) | T3 |
| 12 | kit GP #8 falsely claims a loop-detection hook | Fix (remove claim; do NOT build hook) | T2 |
| 13 | `pre-completion-checklist.py` dark feature + 2 bugs (env session_id; legacy deny shape) | Fix (subsumed by Codex 1/10 redesign — record/gate split + state hardening) | T3 (code), T9 (install), T10 (README), T5 (snippet) |
| 14 | `stop-verify.sh` needs 3 fixes (exit 2/stderr; visible output; loop guard) | Fix (loop guard upgraded to bounded policy per Codex 2) | T4 |
| 15 | `settings-snippet.json` wrong (flat) schema | Fix (nested schema — Stop + PreToolUse + PostToolUse) | T5 |
| 16 | Land `skills/review.md` | Fix (as-is) | T7 |
| 17 | Land `decision-record-template.md` | Fix (as-is) | T6 |
| 18 | Land `eval-template.md` | Fix (as-is) | T6 |
| 19 | Land `escape-hatch-audit.md` w/ provenance fix | Fix (cite Playbook Ch. 18b) | T6 |
| 20 | Land kit GP #17-18; README "16"→"18" | Fix | T2 (doc), T10 (2 counts) |
| 21 | Merge AGENTS-additions into AGENTS.md (2 Never Do bullets + Orchestration) | Fix | T8 |
| 22 | Land `context-inheritance-audit.md` | Fix (as-is) | T6 |
| 23 | README per README-additions + install new artifacts | Fix | T10 (README), T9 (install) |
| 24 | Add CI: shellcheck + smoke; badge; Makefile decision | Fix (no Makefile; smoke T11a + CI T11b, Linux+macOS) | T11a, T11b, T10 (badge) |

**Count: 24 findings → 24 dispositions (24 Fix, 0 Deferred, 0 False positive).**

## Traceability — Codex round-1 findings (12)

| # | Codex finding | Disposition | Task(s) |
|---|---|---|---|
| C1 | Checklist records verification at PreToolUse (before execution); compound `test && commit` early-returns without gating | Fix (record at PostToolUse, gate at PreToolUse; reject commit/echo/interrupted) | T3, T5 (PostToolUse group), T11a (Test E) |
| C2 | Stop-hook loop guard via grep; no bounded re-run policy | Fix (structural `python3` parse; first-stop block, active-stop re-run→warn-allow) | T4, T11a |
| C3 | Installer clobbers coexisting setups (`.git` dir check, hardcoded `.git/hooks`, false success on existing config, Cursor dir check) | Fix (git-toplevel gate, `git-path hooks`, foreign-config WARNING, file check, `.harness/hooks` skip-if-exists) | T9 |
| C4 | Raw-hook backup silently disables the existing hook | Fix (preserve → `<hook>.harness-preserved`, chain first with non-zero propagation; refuse on name clash; marker-based ownership) | T9, T11a (chaining test) |
| C5 | Uninstall is destructive (`rm -rf`, blanket `pre-commit uninstall`) | Fix (enumerate owned files, `rmdir` only-if-empty, restore preserved, remove wrappers by marker, config only-if-ours) | T10 |
| C6 | Smoke coverage thin; no fatal-on-setup, idempotency, stop-verify, stamp edges, chaining; no macOS | Fix (`run_or_die`; completeness/idempotency/stop-verify/stale+future/chaining; macOS CI job) — **assertion count grown to 22 and idempotency strengthened in round-2, see R4/R5** | T11a, T11b |
| C7 | Task 1: `git add` of deleted+ignored path errors; `docs/.DS_Store` missed; no `__pycache__`/`*.pyc` ignore | Fix (`git add LICENSE .gitignore`; remove `docs/.DS_Store`; ignore bytecode) | T1 |
| C8 | Hook command paths assume cwd; Stop matcher present | Fix (`${CLAUDE_PROJECT_DIR}` in commands; `cd` in stop-verify; omit Stop matcher) | T5, T4, T10 |
| C9 | Stop hook guesses commands (runs missing scripts; `python`; network `tsc`) | Fix (script-exists guards; `python3 -m pytest`; trust warning) — **typecheck command superseded by S6 (`./node_modules/.bin/tsc`, not `npx --no-install`)** | T4, T10 |
| C10 | State file world-readable, stores command text, unscoped key, no shape validation | Fix (`0600` in `0700` per-user dir; atomic replace; `{category,time}` only; key = sha256(session+repo); validate/reset) | T3 |
| C11 | Review skill not a real CC skill | Fix (installer generates `.claude/skills/review/SKILL.md` = frontmatter + body; skip-if-exists) | T9, T10, T11a |
| C12 | Stamp age edges: future-dated stamp slips past stale check | Fix (reject age `< 0`: block, delete, message; compare in seconds) | T3, T11a |

**Codex count: 12 findings → 12 dispositions (12 Fix, 0 Deferred, 0 False positive).** Two design alternatives Codex raised (install manifest; `.harness/verify.sh` single-command Stop entrypoint) are explicitly **deferred to v1.1** in NOT-in-scope with rationale.

## Traceability — Codex round-2 findings (6 blockers + 7 secondaries)

**Verified protocol-fact corrections (supersede round-1).** Round-1 wrongly claimed "there is no `PostToolUseFailure` event." Re-verified against the Claude Code hook reference: `PostToolUseFailure` **exists**, and `PostToolUse` fires **only on tool success**. Consequences threaded through the plan: the checklist registers **only `PostToolUse`** for recording (not a failure variant), record payloads **drop `tool_response.interrupted`** (a fired PostToolUse already implies success), the hook keys state on the event **`cwd`** (not `os.getcwd()`), the PreToolUse deny keeps the `hookSpecificOutput.permissionDecision` form (both deny forms are valid), the Stop group **omits `matcher`**, and command strings use `${CLAUDE_PROJECT_DIR}` (expanded and exported). These corrections are reflected in the Context Brief, Task 3, Task 4, and Task 5.

| # | Codex round-2 finding | Disposition | Task(s) |
|---|---|---|---|
| R1 | Success-only `PostToolUse` still fires for `npm test \|\| true`; `should_record` accepted any command text as a verification | Fix (anchored `should_record`: reject `\|\| ; \| & $( ` backtick/newline, split on `&&`, allow leading `cd`, each segment must match an approved verifier) + 3 smoke negatives | T3, T11a |
| R2 | Stop-hook loop guard relied on `stop_hook_active`, which the docs document only on SubagentStop — a real Stop loop could slip through | Fix (second, field-independent guard: per-session block counter in the 0700 dir; ≥2 blocks in 10 min → warn-allow; reset on green) + 3rd smoke case | T4, T11a |
| R3 | Raw-hook install trusts `core.hooksPath` / could write through a symlink outside the repo | Fix (resolve hooks dir to physical abs path, require containment under toplevel or git-dir else REFUSE; refuse if target hook is a symlink; both `return 1`, leave `HOOKS_ACTIVE=false`) | T9 |
| R4 | Chaining + idempotency smoke assertions too weak (file-set only) | Fix (content+mode idempotency; chaining asserts the preserved hook still runs) — **the round-2 landing was incomplete (chaining stayed at 2 asserts; snapshot still pruned `.git/hooks`); completed in R3-4 with a python snapshot, superseding the `cksum`/`ls` approach (R3-5)** | T11a |
| R5 | Installer path nondeterministic under test (depends on whether `pre-commit` is present) | Fix (`HARNESS_KIT_HOOK_MODE` seam: direct/precommit/auto; smoke forces modes; 3rd CI job runs `precommit`; `CLAUDE_PROJECT_DIR` set on stop-verify fixtures) | T9, T11a, T11b |
| R6 | Closing banner unconditionally printed "installed successfully" even when the foreign-config branch left hooks unwired | Fix (`HOOKS_ACTIVE` tracked; closing block prints "Git hooks are NOT active" unless truly wired) + foreign-config smoke scenario | T9, T11a |
| S1 | Stamp age compared in whole minutes (a stamp 30–59 s stale rounded to 0) | Fix (compare in seconds: `age_seconds > MAX_AGE_MINUTES*60`) | T3 |
| S2 | Task 1 checked `git status` before staging LICENSE/.gitignore | Fix (stage first, then status/commit) | T1 |
| S3 | `load_state` trusted the JSON shape (a hand-edited state file could crash or mis-gate) | Fix (validate top-level dict + each entry's `{category,time}` types; reset to empty on any mismatch) | T3 |
| S4 | State dir used without validating it is a real, private, self-owned dir | Fix (`lstat`: must be a real dir, non-symlink, uid==caller, mode 0700; else fall back to `mkdtemp`) — **the `mkdtemp` fallback was superseded by round-3 S4′ (fail closed via `StateDirError`, no fallback)** | T3 |
| S5 | `package.json` script detection by grepping raw text | Fix (parse with `python3 -c 'import json…'`, check `scripts.test`/`scripts.lint`) | T4 |
| S6 | Typecheck used deprecated `npx --no-install tsc` | Fix (`./node_modules/.bin/tsc --noEmit` only if executable; else skip) | T4 |
| S7 | `ci.yml` lacked least-privilege token scope and per-job timeouts | Fix (`permissions: contents: read`; `timeout-minutes` on every job) | T11b |

**Round-2 count: 13 findings → 13 dispositions (13 Fix, 0 Deferred, 0 False positive).** Smoke assertion count after round 2: **22** (was 16).

## Traceability — Codex round-3 findings (7 blockers + 6 secondaries + 1 delta + 1 advisory)

**Externally-verified facts (round 3).** Where Codex asserted a checkable external fact, I verified it rather than transcribing: (1) **pre-commit refuses to install when `core.hooksPath` is set** — confirmed against `pre_commit/commands/install_uninstall.py` ("Cowardly refusing to install hooks with `core.hooksPath` set"); drives R3-1. (2) **A linked worktree's hooks live under `git rev-parse --git-common-dir`**, which is under neither `--show-toplevel` nor `--absolute-git-dir` — confirmed by creating a real worktree (`--git-path hooks` → `main/.git/hooks`, `--show-toplevel` → the linked dir); drives R3-2. (3) **The CC docs DO document Stop exit-2 blocking** — confirmed against the live "Exit code 2 behavior per event" table (Stop → "Prevents Claude from stopping, continues the conversation"); corrects the round-1/2 "docs-silent" claim (R3-7 wording; guards kept as defense-in-depth).

| # | Codex round-3 finding | Disposition | Task(s) |
|---|---|---|---|
| R3-1 | `smoke-precommit` fails by design: smoke pins `core.hooksPath` (pre-commit refuses); `install_precommit_framework` runs inside `if`/`elif` (set -e suspended) so a failed `pre-commit install` still sets `HOOKS_ACTIVE=true` | Fix (smoke uses `GIT_CONFIG_GLOBAL/SYSTEM=/dev/null`, drops the `core.hooksPath` pin; installer uses `pre-commit install \|\| return 1` for both hook types; CI pins the pre-commit version) | T9, T11a, T11b |
| R3-2 | R3 containment `mkdir -p`s the hooks dir BEFORE validating (creates a refused external dir); rejects legitimate linked-worktree hooks under the common dir | Fix (resolve with `realpath` before any mkdir; allow containment under toplevel OR absolute-git-dir OR **git-common-dir**; preflight both targets + symlinks + preserved collisions before writing; direct mode refusal is fatal) | T9 |
| R3-3 | R1 allows a leading `cd <path>` so `cd ../other && npm test` authorizes THIS repo; `has_project`/state keyed on literal cwd (subdir commit misclassified); `COMMIT_PATTERN` misses `git -C`, `git -c`, `/usr/bin/git` | Fix (drop the inline-`cd` allowance; key state + marker check on canonical project root; broaden `COMMIT_PATTERN`) — **project-root ordering superseded by round-4 R4-1: git top-level of `cwd` first, `CLAUDE_PROJECT_DIR` only a fallback** | T3, T11a |
| R3-4 | R4 never landed: chaining still asserted only 2 things; idempotency `snapshot()` prunes ALL of `.git`, so `.git/hooks` is invisible | Fix (5 chaining assertions incl. preserved content+mode + wrapper marker + blocked commit; snapshot includes `.git/hooks`, prunes only volatile git internals, keeps content+mode) | T11a |
| R3-5 | Smoke fails its own shellcheck gate: `ls -ld \| awk` (SC2012); single-quoted hook-body assignments (SC2016) | Fix (python-stdlib snapshot; scoped `# shellcheck disable=SC2016` on the two wrapper-body assignments) | T9, T11a |
| R3-6 | `CONFIG_FOREIGN` is one unanchored grep (partial merge passes); `precommit` mode skips the foreign branch entirely; refusal banner prints irrelevant "merge" text | Fix (refuse foreign/partial in precommit too; validate `HOOK_MODE`∈{auto,direct,precommit}; track `INACTIVE_REASON`; re-derive the exact Old banner text from the real file) — **the string-validation of hook entries is superseded by round-4 R4-3: byte-identity (`cmp -s`) against the shipped config; anything not byte-identical is foreign** | T9, T11a |
| R3-7 | R2 counter uses a blind `mkdir -p`+`chmod` (follows a pre-planted symlink); keyed by session only (repo A loop warn-allows repo B); no numeric validation of counter lines | Fix (reuse the checklist's lstat-validated state dir via one python3 call; key on session + canonical project root; numeric-validate lines before arithmetic; prune expired) | T4 |
| S3′ | `load_state` checks key presence, not value types (a string `time` crashes `now - time`) | Fix (type-check `category` is str and `time` is a real number, bool excluded) | T3 |
| S4′ | `state_dir` fallback `mkdtemp()` per-invocation → gate can never find recorded state | Fix (stable dir; **fail closed** — raise `StateDirError`; the gate then denies with a diagnostic instead of silently mis-scoping) | T3 |
| S-counter | Counter smoke didn't assert blocks 1 and 2 each exit 2 | Fix (both priming blocks asserted at exit 2) | T11a |
| S-foreign | Foreign-config smoke didn't assert installer exit 0 or config unchanged | Fix (both asserted: exit 0 + content-and-mode `cmp`) | T11a |
| S-uninstall | Uninstall checklist could restore a preserved hook without first removing our wrapper | Fix (restore only after positively identifying + deleting the harness wrapper) | T10 |
| S-prose | "The installer only adds files" is inaccurate (gitignore append, framework hooks, rename/chain) | Fix (prose corrected) | T10 |
| D1 | Stale smoke header comment ("CI runs this without the pre-commit framework") contradicts the smoke-precommit job | Fix (header reworded to describe the seam + both CI paths) | T11a |
| ADV | Compound "Run:" one-liners (T4 Step 3, T9 Step 13, T7 Step 2) violate one-command-per-Bash-call | Fix (plan-wide implementer note added; see the note under Tasks) | plan note |

**Round-3 count: 14 findings → 14 dispositions (14 Fix, 0 Deferred, 0 False positive).** The 14 are the 7 blockers (R3-1..R3-7) + 6 secondaries (S3′, S4′, S-counter, S-foreign, S-uninstall, S-prose) + the D1 plan-doc delta. The **ADV** row (compound `Run:` one-liners) is a plan-hygiene process note listed for completeness in the 15th row — it is **not** an audit finding and is not counted in the 14. New smoke assertion count: **30** (was 22) — the eight additions are the 4 extra chaining assertions (R3-4), 2 counter-priming assertions, and 2 foreign-config assertions; the idempotency and snapshot were strengthened in place.

## Traceability — Codex round-4 findings (6 blockers + 3 corrections + 1 plan-doc delta)

**Conservative-option note (round 4).** Round 5 is the final gate, so wherever Codex offered a choice I took the stricter branch: R4-3 treats **any** non-byte-identical pre-existing `.pre-commit-config.yaml` as foreign (no structural "is it good enough" parsing), and the state-dir failures (R4-4/R4-5) **fail closed** — the gate denies and the Stop hook still emits both guards rather than degrading open.

| # | Codex round-4 finding | Disposition | Task(s) |
|---|---|---|---|
| R4-1 | `project_root` preferred `CLAUDE_PROJECT_DIR` over the event `cwd`, so a stale/exported env var from another repo could key state to the wrong project (cross-repo authorization escape) | Fix (resolve the git top-level from the event `cwd` **first** via `git -C cwd rev-parse --show-toplevel`; `CLAUDE_PROJECT_DIR` is only a fallback and only when `cwd` is inside it; 3 smoke cases: subdir still gated, repo-2 verify doesn't authorize repo-1, repo-1 state not consumed by repo-2) | T3, T11a |
| R4-2 | `install_raw_git_hooks` reported success after a failed write: `set -e` is suspended left of `\|\|`, so `write_raw_hook` could `printf`/`chmod`-fail and still fall through to `HOOKS_ACTIVE=true` | Fix (`write_raw_hook` returns non-zero on any `mv`/`printf`/`chmod` failure with per-hook rollback of the preserved original; validates the marker hook is executable before claiming idempotent success; caller sets `INACTIVE_REASON` and returns 1 so the banner reports NOT active) | T9, T11a |
| R4-3 | `config_is_harness_complete` was still a set of substring greps — a hand-merged or partial config with the right strings in the wrong order/stage would pass as "ours" | Fix (**supersedes the R3-6 string-validation approach**: `cmp -s` byte-identity against the shipped `.pre-commit-config.yaml`; anything not byte-identical is foreign and the framework path stays inactive; near-miss smoke fixture with all three strings but a wrong `stages:` value asserts foreign) | T9, T11a |
| R4-4 | Fail-closed was incomplete: `state_dir` raised bare `OSError` on an unwritable base, and the gate caught only `StateDirError`, so an `OSError` escaped and crashed the gate (fail-open) | Fix (wrap every `OSError` as `StateDirError`; `os.makedirs(base, mode=0o700)` with **no** `exist_ok` + re-`lstat` after creation for TOCTOU; the gate catches `(StateDirError, OSError)` and emits a PreToolUse **deny** decision; insecure-state-dir smoke case via a symlinked temp dir asserts the gate denies) | T3, T11a |
| R4-5 | The Stop hook lost **both** loop guards on a state-dir error: the embedded `secure_state_dir()` raised, so neither `stop_hook_active` nor the counter was consulted and the hook fell through | Fix (the embedded helper catches `OSError` and returns `""` — never raises; `stop_hook_active` is always parsed and printed; the counter degrades to empty rather than crashing, so guard 1 always survives a state-dir failure) | T4 |
| R4-6 | A malformed `# shellcheck` directive line in the smoke source (line began with the directive but wasn't a valid disable) would itself trip the shellcheck gate | Fix (reworded to an ordinary comment; no smoke line begins with a `# shellcheck` token that isn't a valid, scoped `disable`) | T11a |
| C1 | Allowlist drift: `APPROVED_RE`/`TEST_RE`/`LINT_RE` missed `python3 -m pytest`, `flake8`, `./node_modules/.bin/tsc --noEmit`, and `cargo check` that other parts of the plan reference | Fix (all four added to the anchored allowlist regexes; `py_compile`-verified) | T3 |
| C2 | Containment had no positive worktree case and no negative external-`core.hooksPath` case in smoke | Fix (2 cases added) — **the worktree half is SUPERSEDED by round-5 R5-1: a linked-worktree install now asserts REFUSAL, not success; the external-`core.hooksPath` half is strengthened by the round-5 snapshot note to a recursive content+mode diff** | T11a |
| C3 | The chaining marker check used a loose `grep` (a comment mentioning the marker elsewhere could match) | Fix (`grep -Fxq '# harness-kit hook'` — fixed-string, whole-line — in both the installer and the smoke assertion) | T9, T11a |
| D-count | Plan-doc delta: the round-3 table header ("7 blockers + 7 secondaries + delta"), its 15 rows, and its "14 → 14 dispositions" summary disagreed | Fix (header now "7 blockers + 6 secondaries + 1 delta + 1 advisory"; summary states the 14 counted = 7 + 6 + D1 and that the ADV row is a listed-not-counted process note; row count and header now agree) | plan doc |

**Round-4 count: 10 items → 10 dispositions (10 Fix, 0 Deferred, 0 False positive)** — 6 blockers (R4-1..R4-6) + 3 corrections (C1–C3) + 1 plan-doc delta (D-count). New smoke assertion count: **37** (was 30) — the seven additions are the 3 cross-repo cases (R4-1a/b/c), the insecure-state-dir case (R4-4), the 2 containment cases (C2: linked-worktree + external-`core.hooksPath`), and the near-miss foreign-config case (R4-3).

## Traceability — Codex round-5 findings (3 blockers + 1 assertion note + 4 plan-doc prose syncs)

**Conservative-option note (round 5).** The final scoped round again took the stricter branch: R5-1 **refuses** a linked-worktree install outright (rather than trying to rewrite the wrappers with absolute paths), and R5-2 makes the two-hook write a full **snapshot/restore transaction** rather than best-effort.

| # | Codex round-5 finding | Disposition | Task(s) |
|---|---|---|---|
| R5-1 | A linked-worktree install writes hooks into the shared common-dir, but the wrappers invoke worktree-local `.harness/hooks/*` paths → commits from the primary worktree (or after the linked one is removed) fail command-not-found | Fix (**refuse** hook wiring from a linked worktree — detect `--absolute-git-dir` ≠ `--git-common-dir`, canonicalized; `INACTIVE_REASON=worktree` + NOT-active banner; applies to BOTH the raw-hook and framework paths and ALL modes, since both write the shared dir; smoke C2 worktree case now asserts REFUSAL + shared dir untouched + primary-worktree commit unaffected) | T9, T11a |
| R5-2 | The two-hook raw install was not transactional: pre-commit written before post-commit, so a post-commit failure (reachable via a marker-owned **non-executable** post-commit) left pre-commit active while the banner said inactive; rollback only handled the moved-foreign case and ignored rollback-`mv` failures | Fix (snapshot BOTH targets + their `.harness-preserved` siblings before any mutation; apply both; on ANY failure restore BOTH with **checked** rollback that reports loudly if a rollback op itself fails; a marker-owned non-executable hook is `chmod`-repaired inside the transaction; new non-exec-marker smoke scenario) | T9, T11a |
| R5-3 | State-dir creation `chmod`'d the base BEFORE the `lstat` validation in both `state_dir` (checklist) and `secure_state_dir` (stop-verify) — a symlink planted in the create window had its TARGET chmod'd | Fix (identical in both: `lstat` immediately after create/`FileExistsError`; verify real dir + owner + non-symlink BEFORE any `chmod`; `chmod` only the validated self-owned dir, then revalidate) | T3, T4 |
| SNAP | The external-`core.hooksPath` smoke assertion only checked `keep.txt` present + `pre-commit` absent — blind to truncation, chmod, or a new file | Fix (generalize `snapshot()` to take an optional dir; assert a recursive content+mode+symlink snapshot of the external dir is byte-for-byte unchanged before/after) | T11a |
| P1 | Context Brief "State-file safety" bullet still said an insecure dir falls back to a fresh `mkdtemp` and keyed state on `(session_id, cwd)` | Fix (fails closed via `StateDirError`; key `(session_id, project_root)`, git-toplevel-of-cwd first; validate-before-chmod noted) | plan doc |
| P2 | Failure Modes masked-failure row still said each `&&` segment is checked "after an optional leading `cd`" (the inline-`cd` allowance was removed in R3-3) | Fix (removed; every segment must match `APPROVED_RE`, no `cd` allowance) | plan doc |
| P3 | Failure Modes installer-false-success row still described the three-entry grep (R3-6) | Fix (byte-identity `cmp -s`, R4-3; any non-identical config is foreign) | plan doc |
| P4 | Failure Modes silent-no-op row still said `sha256(session_id + cwd)` | Fix (`sha256(session_id + project_root)`, R3-3/R4-1) | plan doc |

**Round-5 count: 8 items → 8 dispositions (8 Fix, 0 Deferred, 0 False positive)** — 3 blockers (R5-1..R5-3) + 1 assertion-strengthening note (SNAP) + 4 plan-doc prose syncs (P1–P4). Two consistency edits followed from the blockers and are folded into the same rows rather than counted separately: the `core.hooksPath`-escape Failure-Modes row and the installer eval criterion now note the R5-1 linked-worktree refusal and the R5-2 transaction. New smoke assertion count: **40** (was 37) — the three net additions are the reshaped worktree case (+2: NOT-active banner, shared-dir-untouched + primary-commit-unaffected, replacing the single success assertion) and the R5-2 non-exec-marker case (+1); the external-`core.hooksPath` case stays one assertion but is now a recursive snapshot diff.

## Self-Review (quality gate)

- **All six traceability tables complete** — 24 original findings + 12 round-1 + 13 round-2 + 14 round-3 + 10 round-4 + 8 round-5 (3 blockers + 1 assertion note + 4 plan-doc prose syncs) Codex findings, every one a Fix with a task reference; the two v1.1 deferrals are Codex design *alternatives*, recorded in NOT-in-scope, and the round-3 ADV row is a listed-not-counted plan-hygiene note. ✔
- **Plan starts with a feature-branch task** (`release-readiness`, T1 Step 1). ✔
- **Vault treated read-only** — every bundle file is a copy; escape-hatch line-6 and AGENTS bullet-2 adaptations are made in the repo copy, never the vault. ✔
- **Verified Claude Code protocol facts encoded** (round-2 + round-3 corrections, checked against live docs): `PostToolUseFailure` exists and `PostToolUse` is success-only, so recording registers **only `PostToolUse`**, drops `tool_response`, and keys on the canonical **project root resolved from the event `cwd` first** (round-4 R4-1 — the git top-level of `cwd`, with `CLAUDE_PROJECT_DIR` only a fallback and only when `cwd` is inside it); **Stop exit-2 blocking IS documented** (round-3 correction — the round-1/2 "docs-silent" claim was wrong), and the two Stop guards are kept as **defense in depth**; PreToolUse `hookSpecificOutput` deny; nested settings schema with `${CLAUDE_PROJECT_DIR}` and omitted Stop matcher. ✔
- **No new frameworks / no non-stdlib deps** — bash + stdlib Python 3; JSON parsed with `python3` (already a dependency), never `jq`. A read-only `git -C cwd rev-parse --show-toplevel` resolves the project root from the event `cwd`, with `CLAUDE_PROJECT_DIR` only as a fallback (R3-3 / round-4 R4-1). ✔
- **Hook safety** — checklist state is `0600` in an `lstat`-validated `0700` per-user dir that **fails closed** on insecure **or unwritable** conditions (S4′; round-4 R4-4 wraps every `OSError` as `StateDirError`, uses `makedirs(mode=0o700)` with no `exist_ok` + a TOCTOU re-`lstat`, and the gate catches both and **denies**), atomic, keyed on the **git top-level of the event `cwd` first** (R3-3 / round-4 R4-1 — no cross-repo env escape), shape- and value-type-validated on load (S3′), no command text; recording only after execution through **anchored** validation (round-4 C1 aligns the allowlist with `python3 -m pytest`/`flake8`/`./node_modules/.bin/tsc`/`cargo check`) with no inline-`cd` escape (R1/R3-3); installer resolves the hooks dir before mutating, allows worktree common-dir containment, refuses external paths/symlinks, treats any **non-byte-identical** pre-existing config as foreign (round-4 R4-3), returns non-zero with rollback on any hook-write failure (round-4 R4-2), checks the chain marker with `grep -Fxq` (round-4 C3), and reports inactivity truthfully with a reason (R3-2/R3-6); the Stop counter shares the same validated dir, is keyed per (session, project), and **never loses either loop guard on a state-dir error** (round-4 R4-5); both state dirs validate ownership + non-symlink **before any `chmod`** so a symlink planted in the create window is never followed (round-5 R5-3); the installer writes both raw hooks as **one snapshot/restore transaction** and **refuses to run from a linked worktree** (round-5 R5-1/R5-2); uninstall restores a preserved hook only after removing our wrapper (S-uninstall). ✔
- **Repo stays docs-only** — no build marker added; Makefile decision stated with rationale. ✔
- **Portability** preserved (Linux + macOS, CI-enforced across raw-hook and pre-commit modes); shellcheck-clean (SC2086/SC2016 disables scoped with reasons; snapshot in python to avoid SC2012; no smoke line begins with a non-`disable` `# shellcheck` token — round-4 R4-6); `touch -t`/`os.stat`/`cmp` are BSD+GNU safe; no `mapfile`/associative arrays (bash 3.2). ✔
- **Deterministic tests** — hermetic git config (`GIT_CONFIG_GLOBAL/SYSTEM=/dev/null`) + the `HARNESS_KIT_HOOK_MODE` seam remove any dependency on the runner's `pre-commit`/global config; CI exercises both install paths with a pinned framework version. ✔
- **Complete file contents / precise diffs** for every change; each task ends with verification then commit; conventional-commit messages throughout. ✔
- **`no-known-broken` honored** — the redesigned hooks are behaviorally verified by the **40-assertion** smoke test (record-after-exec, R1 negative recordings, deny/allow, 3 cross-repo isolation cases (R4-1a/b/c), insecure-state-dir fail-closed (R4-4), stop-verify all guard paths incl. both priming blocks, stale+future stamp, 5-way chaining, content+mode idempotency incl. `.git/hooks`, foreign-config banner + config-unchanged, near-miss foreign config (R4-3), linked-worktree **refusal** + shared-dir-untouched + primary-commit-unaffected (R5-1), non-exec-marker in-transaction repair (R5-2), and an external-`core.hooksPath` refusal verified by recursive snapshot (SNAP)), not just asserted. ✔
