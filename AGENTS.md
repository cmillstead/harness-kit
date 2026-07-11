# AGENTS.md

## What This Project Is
<!-- Replace with 1-2 lines about the project purpose and why correctness matters -->

## Commands
<!-- Replace with your project's actual commands -->
```
npm run build        # Production build
npm test             # Run all tests
npm run lint         # Lint check
npm run lint:fix     # Auto-fix lint issues
```

## Architecture
<!-- Replace with your project's layer structure -->
<!-- Example: -->
<!-- Types → Config → Repo → Service → Runtime → API -->
<!-- Lower layers MUST NOT import from higher layers. -->
<!-- Read docs/architecture.md when: working on cross-layer changes. -->

## Code Style
<!-- Replace with project-specific conventions -->
- NEVER use `any` in TypeScript — use `unknown` if the type is genuinely unknown
- NEVER swallow errors with empty catch blocks — at minimum, log them
- NEVER use default exports — use named exports only
- Comments explain WHY, not WHAT

Read docs/code-style.md when: writing Python, TypeScript, Angular, JavaScript, HTML, or SCSS.

## Testing
- Use real implementations in tests — NEVER use mocks, patches, or stubs
- The ONLY exception: external paid APIs with no sandbox (add `# mock-ok: <reason>`)
- Unit tests colocated with source files
- YOU MUST write tests for new business logic

## Always Do
- Run tests and linting before committing
- Follow the architectural layer structure
- Use existing utilities before creating new ones
- Write tests alongside new code
- Use descriptive names — NEVER use single-letter variables outside loops

## Ask First
- Adding a new external dependency
- Modifying database schema or migrations
- Changing public API contracts or interfaces
- Deleting or moving files in shared directories
- Any change affecting more than 3 modules

## Never Do
- NEVER commit secrets, tokens, API keys, or credentials
- NEVER modify deployed migration files
- NEVER skip or disable tests to make CI pass
- NEVER force push to main or release branches
- NEVER commit .env files or sensitive configuration
- NEVER introduce a new framework or library without explicit approval
- NEVER claim work is done without running verification (tests, lint, typecheck)
- NEVER retry the same failed approach more than 3 times — escalate instead
- NEVER construct a reason why a particular edit "doesn't count" as a code change.
  Updating test expectations, changing string literals, fixing typos, renaming variables —
  these are ALL code changes. If you are building a rationale for why a specific edit is
  exempt from a rule, that rationale is the signal to follow the rule.
- NEVER edit agent configuration files directly just because they use a `.md` extension
  (skill definitions, prompt templates, workflow specs). They are configuration, not
  documentation — route changes through your normal process.

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

## Golden Principles
Read docs/golden-principles.md when: making architectural decisions or resolving ambiguity.

## More Information
<!-- Add pointers to detailed docs -->
<!-- - Architecture: docs/architecture.md -->
<!-- - Testing strategy: docs/testing.md -->
<!-- - API contracts: docs/api-contracts.md -->
