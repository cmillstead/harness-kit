# Decision Record Template

> Store in `docs/decisions/YYYY-MM-DD-short-title.md`
> See: Harness Engineering Playbook, Chapter 3 (Context Engineering)

Use this template to capture the *why* behind decisions — the context that instruction files and architecture docs miss. An agent that sees only the outcome will get the reasoning wrong. A decision record prevents that.

---

## [Short title — what was decided]

**Date**: YYYY-MM-DD
**Status**: Accepted | Superseded by [link] | Deprecated
**Deciders**: [who was involved]

### Context

What situation or problem prompted this decision? What constraints were in play? Include organizational context an outsider (or an agent) wouldn't know.

### Decision

What was chosen. One or two sentences.

### Alternatives Considered

| Option | Pros | Cons | Why not |
|--------|------|------|---------|
| [Alternative 1] | | | |
| [Alternative 2] | | | |

### Consequences

What changes as a result. What becomes easier. What becomes harder. What an agent should or should not do because of this decision.

### What NOT to Do

Explicit prohibitions that follow from this decision. An agent reading this section should know what actions are off-limits.

---

## Tips

- Write these within 24 hours of the decision, while context is fresh
- Keep them short — one page max. If it needs more, the decision might need decomposing.
- The "What NOT to Do" section is the most valuable part for agents. Prioritize it.
- Link from AGENTS.md using "Read when:" triggers: `Read docs/decisions/2026-03-21-auth-migration.md when: modifying authentication code`
- Review quarterly. Mark superseded decisions. Delete nothing — the history of *why* is as valuable as the current state.
