# Golden Principles

Tiebreakers for ambiguous decisions. Referenced by any AI agent working in this codebase.

---

## Core Principles

The 10 foundational principles of harness engineering (Ch. 2.10).

### 1. The Model Is Commodity; The Harness Is Moat
Models are democratized — everyone can access similar capability. The competitive advantage is not the model. It's the constraints, context, verification, and feedback loops you build around it.

### 2. Constrain, Inform, Verify, Correct
These four verbs are the complete set of levers. Every harness decision falls into one of these categories. If you're missing one, your harness has a hole.
- **Constrain**: architectural boundaries, linter rules, hooks
- **Inform**: context engineering, instruction files, progressive disclosure
- **Verify**: tests, structural checks, observability, pre-completion checklists
- **Correct**: self-healing linters, error recovery, garbage collection, feedback loops

### 3. Smaller Model, Better Context
Well-curated context with a cheap model beats a frontier model with messy context. Invest in information quality, not model size. Haiku with 4K tokens of the right files outperforms Opus with 100K tokens of everything.

### 4. Constraints Are Clarity, Not Limitations
Constraints don't limit agent capability — they amplify it. An unconstrained agent wastes tokens negotiating ambiguity. A constrained agent focuses all capacity on the actual task.

### 5. Harness Decisions Are Infrastructure, Not Prompts
Prompts are brittle — they change with every edit. Harness decisions are architectural — they change agent behavior without changing the agents. A linter rule, a git hook, a CI gate. Invest in infrastructure that persists.

### 6. Verification Is Foundational
You cannot improve what you cannot measure. You cannot maintain a system you do not observe. Tests, metrics, observability — these are not nice-to-haves. They are the foundation.

### 7. Correction Must Be Automated
Manual correction does not scale. Every time an error happens, a human cannot fix it. The harness must correct itself — self-healing linters, feedback loops, error recovery, remediation instructions in error messages.

### 8. Entropy Always Increases; Manage Deliberately
Systems decay. They accumulate technical debt. They drift. Agents amplify this at 10-100x human velocity. One bad pattern becomes fifteen before anyone notices. Entropy management is not a one-time thing — it is continuous.

### 9. The Harness Is a System, Not a Checklist
Each of the four verbs depends on the others. You cannot constrain without informing. You cannot verify without constraints. You cannot correct without verification. They form a closed loop. Design the harness as a system.

### 10. Scale Your Harness Before Scaling Your Agent Count
You can run one agent without a harness. You cannot run ten. Build the harness first. Build it strong. Then scale agents knowing the harness keeps them coherent.

---

## Operational Rules

Practical rules derived from case studies and production experience.

### 11. Real Over Mocks
Use real implementations in tests. NEVER mock what you can run locally. Real tests catch real bugs. Mocks test your assumptions about the dependency, not the dependency itself.
- **Enforcement**: `no-mocks` git hook blocks mock patterns
- **Escape hatch**: `# mock-ok: <reason>` on the line

### 12. Repository Is Source of Truth
If it's not in the repo, it doesn't exist for agents. Architecture decisions, naming conventions, domain rules — commit them or lose them. Not Slack. Not Confluence. Not tribal knowledge.

### 13. Negative Rules Are Stronger
"NEVER do X" triggers avoidance. "Do Y" competes with training data. Pair every positive convention with a negative prohibition. Use NEVER and IMPORTANT markers for critical rules.

### 14. Progressive Disclosure
Root instruction files are maps, not manuals. Keep AGENTS.md under 100 lines. Keep CLAUDE.md under 200 lines. Point to `docs/` for depth. Agents load detail on demand via "Read when:" triggers.

### 15. Instruction Clarity Beats Model Capability
Across every case study — OpenAI, Stripe, Steinberger, Mercari, Spotify — the highest ROI came from clearer instructions, not better models. Detailed specs beat smart inference. Explicit examples beat implicit learning. Written rules beat training loops.

### 16. Observation Is Second-Highest Leverage
After constraint design, invest most heavily in observability. Task completion rate, iteration count, escalation rate, code quality scores. Monitor agent behavior, not just infrastructure health. The observation system determines what gets escalated to humans.

### 17. Verify Before Claiming Done
NEVER claim work is complete without running verification commands. Evidence before assertions. Run tests, linters, type checks — then report. An agent that passes all tests and skips edge cases has satisfied the letter, not the spirit.
- **Enforcement**: `pre-commit-verify` git hook blocks commits without verification stamp

### 18. Bounded Iteration
If the same fix fails 3 times, STOP. Escalate to human with context: what you tried, what failed, what you think the problem is. Doom loops waste tokens, money, and context window.
- **Enforcement**: loop detection hook tracks repeated failures

### 19. Ask Before High-Impact Changes
Adding dependencies, modifying schemas, changing public APIs, deleting shared files — these affect the team and the project's long-term direction. Pause and confirm before proceeding.

### 20. Boring Technology Wins
Prefer composable, API-stable, well-represented-in-training-data tools. Agents perform better with technology they've seen extensively during training. Choose Express over a custom framework. Choose PostgreSQL over a niche database. Choose standard patterns over clever abstractions.
