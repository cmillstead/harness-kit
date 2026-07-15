# Harness Kit

[![CI](https://github.com/cmillstead/harness-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/cmillstead/harness-kit/actions/workflows/ci.yml)

Universal harness for AI-assisted development. Works with any coding agent — Claude Code, Codex, Cursor, Aider, or custom agents.

Based on *The Harness Engineering Playbook* (Cevin Millstead, 2026).

## Install

```bash
# 1. Clone the kit somewhere stable
git clone https://github.com/cmillstead/harness-kit.git /path/to/harness-kit

# 2. From your project root, run the installer
cd /path/to/your/project
/path/to/harness-kit/install.sh
```

## What It Creates

| File | Purpose | Agent |
|------|---------|-------|
| `AGENTS.md` | Universal instruction file with three-tier boundaries | Codex, Copilot, Claude, all |
| `CLAUDE.md` | Thin wrapper for Claude Code | Claude |
| `.cursor/rules/harness.md` | Thin wrapper for Cursor | Cursor |
| `docs/golden-principles.md` | 18 operational rules for agents | All |
| `docs/harness-philosophy.md` | 10 foundational principles (human reference) | — |
| `docs/code-style.md` | Language-specific style rules (example — customize for your stack) | All |
| `.harness/hooks/no-mocks.sh` | Git hook: block mocks in tests | All (git-level) |
| `.harness/hooks/pre-commit-verify.sh` | Git hook: require test/lint before commit | All (git-level) |
| `.harness/hooks/post-commit-cleanup.sh` | Git hook: delete the verification stamp after commit | All (git-level) |
| `.pre-commit-config.yaml` | Hook configuration | All |
| `skills/review.md` | Structural code-audit skill | All |
| `.claude/skills/review/SKILL.md` | Claude Code skill form of `skills/review.md` (frontmatter + body) | Claude Code |
| `docs/decision-record-template.md` | Capture the "why" behind decisions | — |
| `docs/eval-template.md` | Domain-specific eval criteria (any team) | — |
| `docs/escape-hatch-audit.md` | 10-step diagnostic for harness failure patterns | — |
| `docs/context-inheritance-audit.md` | Matrix audit for multi-agent context wiring | — |
| `.claude/hooks/stop-verify.sh` | Stop hook: tests/lint/typecheck before finishing | Claude Code |
| `.claude/hooks/pre-completion-checklist.py` | PreToolUse hook: verify before commit/push | Claude Code |
| `.claude/hooks/settings-snippet.json` | Settings to wire up the Claude Code hooks | Claude Code |

## Architecture

```
Layer 1: Universal (git hooks + AGENTS.md + golden principles)
  ↓ works with any agent
Layer 2: Tool-specific thin wrappers (CLAUDE.md, .cursor/rules/)
  ↓ points back to Layer 1
Layer 3: Dynamic harness (agent hooks + skills)
  ↓ event-driven control + modular instructions
Layer 4: Tool-specific features (Claude hooks, Cursor hooks)
  ↓ cannot be abstracted
```

Layer 3 is the dynamic layer — Stop/PreToolUse hooks and skills that act at runtime, from Playbook Ch. 12b.

All instruction files use **progressive disclosure** — root files are maps, not manuals. They point to `docs/` for detail. Agents load what they need on demand.

## Verification Workflow

```bash
# Run tests and lint, create verification stamp
npm test && npm run lint && touch .harness-verified

# Commit (pre-commit hook checks the stamp)
git commit -m "feat: your change"

# Stamp auto-deleted after commit — must re-verify next time.
# The stamp also expires 30 minutes after creation; a stale stamp is
# rejected and deleted, so re-run tests/lint if you paused mid-change.
```

Docs-only repos (no `package.json`, `Cargo.toml`, etc.) skip verification automatically.

## What's Inside

### AGENTS.md
Template with placeholder sections for your project. Includes:
- **Commands** — build, test, lint commands for your stack
- **Architecture** — layer structure and dependency rules
- **Code Style** — pointer to `docs/code-style.md`
- **Three-tier boundaries** — Always Do / Ask First / Never Do
- **Golden Principles** — pointer to `docs/golden-principles.md`

### Golden Principles
18 operational rules that change agent behavior. Not philosophy — actionable tiebreakers. Examples: "Real over mocks," "Bounded iteration," "Consolidate before adding," "Define exceptions by purpose, not format."

### Harness Philosophy
10 foundational principles for the human architect designing the harness. These guide *you*, not the agent. Examples: "The model is commodity; the harness is moat," "Constrain, inform, verify, correct."

### Code Style
Example language-specific rules covering Python, TypeScript/Angular, JavaScript, HTML, and SCSS. **This is a starting point** — customize for your stack. Remove languages you don't use, add rules for ones you do. The point is to capture conventions that linters can't enforce and agents commonly get wrong.

### Git Hooks
- **no-mocks.sh** — blocks mock/patch/stub usage in test files with remediation instructions guiding toward real implementations
- **pre-commit-verify.sh** — blocks commits unless tests and linting have been run (stamp-based workflow)
- **post-commit-cleanup.sh** — removes the verification stamp after commit so you must re-verify next time

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

> **Nudge vs. enforcement.** The Claude Code commit gate is a *nudge* — it reminds the agent to verify before committing, and detects commit/push across common forms (including wrapper prefixes like `env`/`bash -c`). It does best-effort, deliberately-simple shell inspection for repo-retargeting (`git -C`, `--git-dir`, `--work-tree`, a chained `cd`), and intentionally does **not** fully parse the shell — an exotic form (e.g. a `cd` inside a subshell that also runs the commit) can slip past the *reminder*. That is acceptable because the **enforcing boundary is the git-level `.harness/hooks/pre-commit-verify.sh` hook**, which blocks any unverified commit at commit time regardless of how git is invoked. The nudge improves the agent's workflow; the git hook is what actually holds the line.

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

**2. Claude Code settings — remove the hook registrations you merged in.** If you followed the install "Next steps" and merged `settings-snippet.json` into `.claude/settings.json`, that file still has `Stop`, `PreToolUse`, and `PostToolUse` entries pointing at the `.claude/hooks/` scripts you just deleted — leave them and Claude Code will error on every stop and tool call. Open `.claude/settings.json` and delete those three harness entries (they reference `.claude/hooks/stop-verify.sh` and `.claude/hooks/pre-completion-checklist.py`). Remove other keys only if they are yours to remove; if the harness entries were the only content, you can delete the file.

**3. Git hooks — restore only after removing our wrapper.** Find your hooks dir with `git rev-parse --git-path hooks`. For each of `pre-commit` and `post-commit`, in this order:

- If the hook file has **no** `# harness-kit hook` marker, it is not ours — leave it, and leave any `<hook>.harness-preserved` sibling, untouched. Do NOT restore over a hook you did not install.
- If the hook file contains `# harness-kit hook`, it is ours — delete it. THEN, and only then, if a `<hook>.harness-preserved` sibling exists it is *your* original that we chained: rename it back (`mv pre-commit.harness-preserved pre-commit`).

Restoring the preserved hook only after positively identifying and removing our wrapper guarantees you never overwrite a live non-harness hook.

**4. `.pre-commit-config.yaml` — inspect before removing.** If it references `.harness/hooks/no-mocks.sh` *and* you had no pre-commit config before installing, it is the harness's copy — delete it. If you merged harness entries into a pre-existing config, remove only those entries by hand. If you enabled the pre-commit framework, also run `pre-commit uninstall && pre-commit uninstall --hook-type post-commit`.

**5. Review by hand — never auto-delete.** `AGENTS.md`, `CLAUDE.md`, and `.cursor/rules/harness.md` are meant to be customized. Open each and remove the harness sections you no longer want, keeping your own edits.

## Customization

1. **AGENTS.md** — fill in placeholder sections (commands, architecture, project description)
2. **docs/code-style.md** — customize for your languages and conventions
3. **docs/golden-principles.md** — add project-specific operational rules
4. **.harness/hooks/** — add project-specific git hooks. To pull a fresh copy of a harness hook after editing it, delete your copy and re-run install.sh (the installer skips files that already exist).
5. **CLAUDE.md / .cursor/rules/** — add tool-specific behavior beyond the universal layer
