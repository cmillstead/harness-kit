# Harness Kit

Universal harness for AI-assisted development. Works with any coding agent — Claude Code, Codex, Cursor, Aider, or custom agents.

Based on *The Harness Engineering Playbook* (Cevin Millstead, 2026).

## Install

```bash
cd /path/to/your/project
~/src/harness-kit/install.sh
```

This creates:

| File | Purpose | Agent |
|------|---------|-------|
| `AGENTS.md` | Universal instruction file | Codex, Copilot, Claude, all |
| `CLAUDE.md` | Thin wrapper for Claude Code | Claude |
| `.cursor/rules/harness.md` | Thin wrapper for Cursor | Cursor |
| `docs/golden-principles.md` | 10 decision-making principles | All |
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

## Verification Workflow

```bash
# Run tests and lint, create verification stamp
npm test && npm run lint && touch .harness-verified

# Commit (pre-commit hook checks the stamp)
git commit -m "feat: your change"

# Stamp auto-deleted after commit — must re-verify next time
```

## Customization

1. Edit `AGENTS.md` — fill in placeholder sections for your project
2. Edit `docs/golden-principles.md` — add project-specific principles
3. Add project-specific git hooks to `.harness/hooks/`
