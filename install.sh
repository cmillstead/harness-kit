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

# Check we're in a git repo
if [ ! -d .git ]; then
    echo "ERROR: Not a git repository. Run from a project root."
    exit 1
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

# 3. Git hooks
mkdir -p .harness/hooks
cp "$HARNESS_KIT/hooks/no-mocks.sh" .harness/hooks/no-mocks.sh
cp "$HARNESS_KIT/hooks/pre-commit-verify.sh" .harness/hooks/pre-commit-verify.sh
cp "$HARNESS_KIT/hooks/post-commit-cleanup.sh" .harness/hooks/post-commit-cleanup.sh
chmod +x .harness/hooks/*.sh
echo "✓ Installed git hook scripts to .harness/hooks/"

# 4. Pre-commit config
if [ -f .pre-commit-config.yaml ]; then
    echo "⟳ .pre-commit-config.yaml already exists — merging manually required"
else
    cp "$HARNESS_KIT/.pre-commit-config.yaml" .pre-commit-config.yaml
    echo "✓ Created .pre-commit-config.yaml"
fi

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
- Store architectural decisions in ContextKeep
- Use codesight-mcp for code navigation instead of reading full files
EOF
    echo "✓ Created CLAUDE.md (thin wrapper pointing to AGENTS.md)"
fi

# 7. Thin Cursor rules wrapper
if [ ! -d .cursor/rules ]; then
    mkdir -p .cursor/rules
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

echo ""
echo "========================================="
echo "Harness installed successfully."
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Edit AGENTS.md — fill in the placeholder sections"
echo "  2. Commit: git add AGENTS.md CLAUDE.md docs/ .harness/ .pre-commit-config.yaml"
echo "  3. Test: touch .harness-verified && git commit -m 'test: harness install'"
echo ""
echo "The verification stamp workflow:"
echo "  npm test && npm run lint && touch .harness-verified"
echo "  git commit -m 'feat: your change'"
echo "  (stamp auto-deleted after commit, must re-verify next time)"
echo ""
