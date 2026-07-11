# Eval Template — Domain-Specific Agent Guardrails

> For any team handing consequential work to AI agents — engineering, legal, marketing, finance, ops.
> No code required. See: Harness Engineering Playbook, Chapter 7 (Verification Beyond Code)

An eval encodes your judgment into a check that runs before, during, or after an agent acts. It's the bridge between what you know and what the machine does.

---

## How to Write an Eval

Answer these five questions for each workflow where an agent handles consequential tasks:

### 1. What is the agent doing?

Describe the specific workflow. Be concrete.

Example: "Reviewing vendor contracts and flagging risk clauses."

### 2. What does "right" look like in YOUR context?

Not in general — in your specific organization, with your specific history and constraints.

Example: "Right means: flagged clauses match our playbook, payment terms account for the informal 60-day agreement with Acme Corp, and IP clauses are escalated if we're in active acquisition talks."

### 3. What has gone wrong before (or could)?

Think about the organizational landmines — the things an outsider wouldn't know.

Example: "Last quarter an intern reviewed a contract and missed that we'd renegotiated payment terms verbally. The vendor sent a collections notice."

### 4. What must the agent NOT get wrong?

These become your eval criteria. Write them as plain-language checks.

Example:
- [ ] Payment terms for Acme Corp must reflect the 60-day agreement, not the standard 30-day template
- [ ] Any IP assignment clause must be flagged for legal review when M&A status is active
- [ ] Indemnification caps must not exceed $2M without CFO sign-off
- [ ] Auto-renewal clauses must be flagged regardless of contract size

### 5. When should these checks run?

| Timing | Use when |
|--------|----------|
| **Before** the agent acts | Preventing the agent from starting work on the wrong input or with wrong context |
| **During** the agent's work | Checking intermediate outputs at phase boundaries |
| **After** the agent finishes | Validating the final output before it reaches a human or a system |

---

## Eval Criteria Format

Write each criterion as a yes/no check. The agent (or a reviewer) should be able to answer definitively.

```
EVAL: [Workflow name]
DOMAIN: [Legal / Marketing / Finance / Engineering / Ops / ...]
LAST UPDATED: [Date]
UPDATED BY: [Name — the person who holds this context]

BEFORE:
- [ ] [Check before the agent starts]
- [ ] [Check before the agent starts]

DURING:
- [ ] [Check at each phase boundary]

AFTER:
- [ ] [Check on final output]
- [ ] [Check on final output]

ORGANIZATIONAL CONTEXT THE AGENT DOESN'T KNOW:
- [Unwritten rule, relationship history, political sensitivity, etc.]
- [These are the things that turn a technically correct output into an organizationally dangerous one]
```

---

## Examples by Domain

### Legal — Contract Review
```
AFTER:
- [ ] Payment terms match the negotiated terms for this specific vendor (check vendor history doc)
- [ ] IP clauses flagged when M&A status is active
- [ ] Indemnification caps within approved limits
- [ ] Non-compete scope reviewed against current market strategy

ORGANIZATIONAL CONTEXT:
- Acme Corp has informal 60-day payment terms (not in the template)
- We are in quiet acquisition talks — IP clauses are existential right now
```

### Marketing — Campaign Launch
```
BEFORE:
- [ ] Target segments checked against brand crisis history (see docs/brand-incidents.md)
- [ ] Messaging tone reviewed for markets where we had public issues

AFTER:
- [ ] Campaign does not reference competitors by name (legal policy)
- [ ] Budget allocation matches CMO's Q2 priority shift (not yet in planning docs)

ORGANIZATIONAL CONTEXT:
- European segment had a brand crisis 8 months ago — tone must be different there
- CMO promised CEO a positioning shift that hasn't been documented
```

### Finance — Projections
```
AFTER:
- [ ] No numbers contradict commitments made to the board last quarter
- [ ] Headcount assumptions match HR's actual hiring plan, not the approved budget
- [ ] Revenue projections for new product line flagged as estimates, not commitments

ORGANIZATIONAL CONTEXT:
- Certain growth numbers are politically sensitive internally even if arithmetically correct
- Board cares about margin this quarter, not revenue — weight the presentation accordingly
```

---

## Maintenance

Evals rot just like documentation. Review quarterly. Update when:
- Organizational context changes (new relationships, new constraints, new leadership priorities)
- A near-miss or failure reveals a gap the eval didn't catch
- The person who wrote the eval leaves — their replacement must review and update

The person who should update evals is the person who holds the context. That's usually a senior person. This is a feature, not a bug — eval maintenance is how institutional knowledge stays alive.
