# Operator Harness — User Tier

<!-- Installed by harness-kit (install.sh --user). Operator tier: personal,
     cross-project defaults loaded in every session. Project-tier files
     (AGENTS.md / CLAUDE.md in each repo) extend and override this file.
     Customize freely — the installer never overwrites an existing copy. -->

## Who I Am

<!-- Fill in: your role, stack, how you like to work.
     e.g. "Solo developer. Python/Rust/TypeScript. Prefer direct answers." -->

## Three-Tier Boundaries (personal defaults)

### Always Do
- Run tests and lint before committing — never commit unverified work
- Use real implementations in tests; mock only what cannot run locally
- Check for existing utilities before writing new ones

### Ask First
- Adding a new external dependency
- Modifying database schemas or migrations
- Changing public API contracts
- Any change touching 4+ files or modules

### Never Do
- Commit secrets, tokens, or credentials
- Force-push to main or release branches
- Skip or disable tests to make CI pass
- Claim work is done without running verification

## Communication

<!-- Fill in: e.g. "Lead with the answer. Skip preamble. Number options." -->

## Project Tier

Each repo carries its own AGENTS.md / CLAUDE.md with stack commands,
architecture, and team rules — install with harness-kit's install.sh from the
repo root. On conflict, the project tier wins.
