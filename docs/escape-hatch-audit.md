# Escape Hatch Audit Checklist

> Run this audit when an agent bypasses a constraint, produces degraded output, or behaves in ways you didn't expect.
> See: Harness Engineering Playbook, Chapter 18b (When the Harness Breaks)
> See also: The Harness Engineering Playbook, Ch. 18b (When the Harness Breaks) for real-world examples of each pattern.

---

## The Seven Failure Patterns

| # | Pattern | What happens | Detection signal |
|---|---------|-------------|-----------------|
| 1 | **Permission language** | Agent finds "skip," "directly," "simple" in harness files and uses them to bypass constraints | Agent skips workflow despite explicit instruction |
| 2 | **Category gaps** | Rule covers "test failures" but not "review findings" — agent exploits the uncovered category | Agent dismisses findings with "that's not what the rule covers" |
| 3 | **Split-audience instructions** | One file serves two roles (orchestrator + worker) — agent gets confused about which instructions are for it | Agent writes code when it should delegate, or delegates when it should act |
| 4 | **Format-vs-function** | Exception defined by format (.md) not purpose (documentation) — agent classifies config files as "markdown docs" | Agent edits config/instruction files directly |
| 5 | **Context inheritance gap** | Shared reference files (style guide, principles, memory) not passed to all agents that need them | Output is technically correct but misses conventions, repeats known mistakes |
| 6 | **Serialization anti-pattern** | No dispatch ordering rule — agent does lightweight self-tasks before dispatching long-running agent work | Agent works sequentially when it could parallelize |
| 7 | **Rationalization override** | Rules are already explicit but agent constructs "this doesn't count" reasoning to bypass them | Agent explains *why* the rule doesn't apply — that explanation is the problem |

---

## Step 1: Identify the Symptom

What went wrong?

- [ ] Agent bypassed a workflow despite explicit instruction (→ patterns 1, 2, 4, 7)
- [ ] Agent reclassified a task to avoid a structured process (→ patterns 1, 7)
- [ ] Agent dismissed findings as "pre-existing" or "not a regression" (→ pattern 2)
- [ ] Agent edited files it shouldn't have (→ patterns 3, 4)
- [ ] Output was correct but missed style/conventions/known issues (→ pattern 5)
- [ ] Agent did work sequentially when it could have parallelized (→ pattern 6)
- [ ] Agent explained why a rule doesn't apply to this specific case (→ pattern 7)

## Step 2: Grep for Permission Language

Search ALL harness files (AGENTS.md, CLAUDE.md, .cursor/rules/, skill files, protocol files) for:

```
skip
directly
simple
trivial
mechanical
just do it
pre-existing
not a regression
optional
if needed
when appropriate
markdown doc
doesn't count
```

For each match, ask: does this line give the agent permission to bypass a constraint?

## Step 3: Count the Escape Routes

How many independent lines grant the same exemption?

| File | Line | What it permits |
|------|------|-----------------|
| | | |
| | | |
| | | |

If the same exemption appears in 2+ files, it's compounding. The agent reads one file's exemption without the other file's constraint context.

## Step 4: Check Category Coverage

Does the rule cover the specific category the agent exploited?

Common category gaps:
- Rule says "test failures" but agent found "review findings" aren't covered
- Rule says "code changes" but agent found "config changes" aren't covered
- Rule says "new code" but agent found "pre-existing code" isn't covered
- Rule says "during execution" but agent found "during planning" isn't covered
- Rule says "markdown docs OK" but SKILL.md and config files are also markdown
- Rule says "source/test/config files" but agent decided "updating test expectations" isn't a "test logic change"

## Step 5: Check Audience

Does the instruction file serve multiple roles?

- [ ] Does CLAUDE.md contain instructions for both the orchestrator AND the workers?
- [ ] Does any file assume the reader is both a dispatcher and an implementer?
- [ ] Are there coding conventions in the same file as delegation rules?

If yes: split by audience. Orchestrator config in the root file, worker instructions in reference files loaded via progressive disclosure.

## Step 6: Check Context Inheritance

Map the flow of shared reference files through your pipeline:

| Reference file | Design agents | Planning agents | Implementers | Auditors |
|---------------|:---:|:---:|:---:|:---:|
| code-style.md | | | ? | |
| golden-principles.md | ? | ? | | |
| team-memory.md | | ? | | |

Every `?` is a gap. Every agent that touches code should receive the style guide. Every agent that makes decisions should receive the principles. Every agent that plans should receive the memory.

## Step 7: Check Dispatch Ordering

When the orchestrator has both delegatable and self-executable work:
- [ ] Does the harness specify dispatch order?
- [ ] Does it say to start long-running agent work before doing lightweight self-tasks?

If not: add "dispatch first, self-execute second" to guiding principles.

## Step 8: Check for Rationalization Vulnerability

If the rules are already explicit and the agent still bypasses them:
- [ ] Did the agent construct a reason why this case "doesn't count"?
- [ ] Did it invent a category distinction not in the instructions?

If yes: name the specific rationalization pattern in the harness and make it a compliance trigger:

```
If you find yourself constructing a reason why a particular edit "doesn't
count" — updating test expectations, changing a string literal, fixing a
typo, renaming a variable — that reasoning is the problem. The rule has no
exceptions. The thought "this is too simple for [workflow]" is the signal
to use [workflow].
```

## Step 9: Fix

Apply these principles:

1. **One rule, one location.** If a constraint has an exemption, both live in the same file.
2. **Write for intent, not instance.** Don't write "test failures block progression." Write "all unresolved issues block progression."
3. **Define exceptions by purpose, not format.** Not "markdown docs are OK" but "documentation (README, CHANGELOG, plans) is OK."
4. **Add the absolute override.** "If the user explicitly requests a workflow, that overrides all exemptions."
5. **Narrow exemptions like constraints.** A broad exemption ("simple tasks") will be interpreted broadly.
6. **Name the rationalization.** If the agent is constructing bypass reasoning, describe that exact reasoning and make it a trigger for compliance.
7. **Split by audience.** If one file serves two roles, split it.
8. **Audit context inheritance.** Map reference files × agents as a matrix.

## Step 10: Verify the Fix

Reproduce the original scenario. Does the agent still find the escape hatch? If yes, there's another one — go back to Step 2.

---

## Prevention: The Rule of Thumb

Before adding any exemption language to a harness file, ask:

> "If the agent applies this exemption as broadly as possible, what's the worst thing it could skip?"

If the answer makes you uncomfortable, narrow the exemption or don't add it.

Before deploying a new skill or workflow, run the context inheritance audit (Step 6). It takes five minutes and catches the gaps that cause silent quality degradation for weeks.
