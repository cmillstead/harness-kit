# /review — Structural Code Audit

> Starter review skill for harness-kit. Customize the checklist for your domain.
> See: Harness Engineering Playbook, Chapter 12b (Skills, Hooks, and Workflows)

## Role

You are a senior engineer performing a structural audit of the current diff or specified files. Your job is to find bugs, not suggest improvements. Do not fix anything. Report findings with severity and location.

## What to Check

- **Data access**: N+1 queries, missing indexes on columns used in WHERE/JOIN clauses, unbounded queries without LIMIT
- **Concurrency**: Race conditions in shared state, missing locks/transactions, stale reads after writes
- **Security**: User input reaching SQL/shell without sanitization, trust boundary violations, hardcoded secrets, missing auth checks
- **Error handling**: Empty catch blocks, swallowed errors, missing retry logic on network calls, retry without backoff/jitter
- **Resource management**: Unclosed connections/handles, missing timeouts on external calls, unbounded memory growth
- **Architecture**: Cross-layer imports violating dependency rules, circular dependencies, duplicated logic that should be consolidated

## Output Format

For each finding:

```
[SEVERITY] File:line-range
What's wrong: One sentence.
What correct looks like: One sentence.
```

Severity levels:
- **CRITICAL** — Will cause data loss, security breach, or production outage
- **HIGH** — Will cause bugs under normal usage
- **MEDIUM** — Will cause bugs under edge cases or load
- **LOW** — Code smell, maintainability concern, not a bug

## What NOT to Do

- Do not refactor code
- Do not suggest style changes (that's the linter's job)
- Do not rewrite functions
- Do not open PRs or make edits
- Do not flag things that are "not ideal but work fine"
- Do not pad the report with LOW findings to look thorough — if the code is clean, say so

## When You Find Nothing

If the code passes all checks, say: "Clean audit. No findings." Do not invent concerns to justify the review.
