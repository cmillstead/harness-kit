# Context Inheritance Audit

> For multi-phase workflows with specialist agents. Run before deploying a new skill, after adding reference files, or when agent output silently degrades.
> See: Harness Engineering Playbook, Chapter 3 (Context Engineering)

---

## Purpose

In a multi-phase workflow, it's easy to wire up task-specific context (the plan, the diff, the spec) and forget shared reference context (style guides, principles, memory). The result isn't a crash or a bypass — it's silent quality degradation that can go undetected for weeks.

## The Audit

### Step 1: List Your Reference Files

These are the shared files that inform agent behavior across phases. Common examples:

| File | Contains | Who needs it |
|------|----------|-------------|
| `docs/code-style.md` | Language conventions, naming, patterns | Any agent that writes or reviews code |
| `docs/golden-principles.md` | Operational decision-making rules | Any agent that makes design or architecture decisions |
| `docs/team-memory.md` | Known landmines, past mistakes, learned patterns | Any agent that plans or implements |
| `docs/decisions/*.md` | Decision records with rationale and constraints | Any agent working in the affected area |
| `AGENTS.md` / `CLAUDE.md` | Project conventions and boundaries | All agents (usually loaded automatically) |

Add your own:

| File | Contains | Who needs it |
|------|----------|-------------|
| | | |
| | | |

### Step 2: List Your Agent Roles

Every distinct agent in your workflow:

| Role | What it does | Phase |
|------|-------------|-------|
| Design workers | Analyze problem from specialist angles | Design |
| Planning worker | Produce implementation plan | Planning |
| Implementer | Write code (TDD) | Execution |
| Spec reviewer | Check code against spec | Audit |
| Simplify auditor | Flag dead code, over-abstraction | Audit |
| Harden auditor | Flag security, resilience issues | Audit |

Add your own:

| Role | What it does | Phase |
|------|-------------|-------|
| | | |
| | | |

### Step 3: Fill the Matrix

For each cell: does the harness explicitly pass this file to this agent?

| Reference file | Design | Planning | Implementer | Spec reviewer | Simplify | Harden |
|---------------|:---:|:---:|:---:|:---:|:---:|:---:|
| code-style.md | | | | | | |
| golden-principles.md | | | | | | |
| team-memory.md | | | | | | |
| decisions/*.md | | | | | | |

Mark each cell:
- **Y** = explicitly passed in dispatch instructions
- **N** = not passed (potential gap)
- **—** = not relevant for this role

### Step 4: Evaluate Each Gap

For every **N** cell, ask:

1. Could this agent produce better output if it had this file?
2. Could this agent make a mistake that this file would prevent?
3. Is there a downstream agent that will copy this agent's patterns? (If yes, the gap compounds.)

### Step 5: Fix

For each confirmed gap, add a line to the dispatch instruction telling the orchestrator to pass the file. The fix is always mechanical — one line per gap.

Check that the fix doesn't bloat the agent's context. If a reference file is large (200+ lines), consider extracting just the relevant section for that role.

---

## When to Run This Audit

- Before deploying a new skill or workflow
- After adding or modifying reference files
- When agent output silently degrades (correct but missing conventions, repeating known mistakes)
- Quarterly, as a maintenance practice
