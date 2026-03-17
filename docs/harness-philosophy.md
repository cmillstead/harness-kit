# Harness Philosophy

The 10 foundational principles of harness engineering.
These guide the human architect designing the harness — not the agent operating within it.

From *The Harness Engineering Playbook*, Ch. 2.10.

---

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
