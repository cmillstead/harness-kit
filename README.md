# Harness Kit

Universal harness for AI-assisted development. Works with any coding agent — Claude Code, Codex, Cursor, Aider, or custom agents.

Based on *The Harness Engineering Playbook* (Cevin Millstead, 2026).

## Install

```bash
cd /path/to/your/project
~/src/harness-kit/install.sh
```

## What It Creates

| File | Purpose | Agent |
|------|---------|-------|
| `AGENTS.md` | Universal instruction file with three-tier boundaries | Codex, Copilot, Claude, all |
| `CLAUDE.md` | Thin wrapper for Claude Code | Claude |
| `.cursor/rules/harness.md` | Thin wrapper for Cursor | Cursor |
| `docs/golden-principles.md` | 16 operational rules for agents | All |
| `docs/harness-philosophy.md` | 10 foundational principles (human reference) | — |
| `docs/code-style.md` | Language-specific style rules (example — customize for your stack) | All |
| `.harness/hooks/no-mocks.sh` | Git hook: block mocks in tests | All (git-level) |
| `.harness/hooks/pre-commit-verify.sh` | Git hook: require test/lint before commit | All (git-level) |
| `.pre-commit-config.yaml` | Hook configuration | All |

## Architecture

```
Layer 1: Universal (git hooks + AGENTS.md + golden principles)
  ↓ works with any agent
Layer 2: Tool-specific thin wrappers (CLAUDE.md, .cursor/rules/)
  ↓ points back to Layer 1
Layer 3: Tool-specific features (Claude hooks, Cursor hooks)
  ↓ cannot be abstracted
```

All instruction files use **progressive disclosure** — root files are maps, not manuals. They point to `docs/` for detail. Agents load what they need on demand.

## Verification Workflow

```bash
# Run tests and lint, create verification stamp
npm test && npm run lint && touch .harness-verified

# Commit (pre-commit hook checks the stamp)
git commit -m "feat: your change"

# Stamp auto-deleted after commit — must re-verify next time
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
16 operational rules that change agent behavior. Not philosophy — actionable tiebreakers. Examples: "Real over mocks," "Bounded iteration," "Consolidate before adding," "Naming is architecture."

### Harness Philosophy
10 foundational principles for the human architect designing the harness. These guide *you*, not the agent. Examples: "The model is commodity; the harness is moat," "Constrain, inform, verify, correct."

### Code Style
Example language-specific rules covering Python, TypeScript/Angular, JavaScript, HTML, and SCSS. **This is a starting point** — customize for your stack. Remove languages you don't use, add rules for ones you do. The point is to capture conventions that linters can't enforce and agents commonly get wrong.

### Git Hooks
- **no-mocks.sh** — blocks mock/patch/stub usage in test files with remediation instructions guiding toward real implementations
- **pre-commit-verify.sh** — blocks commits unless tests and linting have been run (stamp-based workflow)
- **post-commit-cleanup.sh** — removes the verification stamp after commit so you must re-verify next time

## Customization

1. **AGENTS.md** — fill in placeholder sections (commands, architecture, project description)
2. **docs/code-style.md** — customize for your languages and conventions
3. **docs/golden-principles.md** — add project-specific operational rules
4. **.harness/hooks/** — add project-specific git hooks
5. **CLAUDE.md / .cursor/rules/** — add tool-specific behavior beyond the universal layer
