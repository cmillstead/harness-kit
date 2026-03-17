# Golden Principles

Ultra-concise rules that resolve ambiguity. Referenced by any AI agent working in this codebase.

## 1. Real Over Mocks
Use real implementations in tests. NEVER mock what you can run locally.
- Escape hatch: `# mock-ok: <reason>` on the line

## 2. Repository Is Source of Truth
If it's not in the repo, it doesn't exist for agents. Commit conventions, architecture decisions, and domain rules — or lose them.

## 3. Smaller Model, Better Context
Well-curated context with a cheap model beats a frontier model with messy context. Invest in information quality, not model size.

## 4. Constraints Over Instructions
Mechanical enforcement beats polite requests. If a rule matters, enforce it with a linter, hook, or test — not just a comment.

## 5. Negative Rules Are Stronger
"NEVER do X" triggers avoidance. "Do Y" competes with training data. Pair every positive convention with a negative prohibition.

## 6. Progressive Disclosure
Root instruction files are maps, not manuals. Keep them short. Point to docs/ for depth. Agents load detail on demand.

## 7. Entropy Is the Enemy
Agents add, they rarely consolidate. One bad pattern becomes fifteen. Clean continuously — never accumulate debt for a "big refactor sprint."

## 8. Verify Before Claiming Done
NEVER claim work is complete without running verification commands. Evidence before assertions. Run tests, linters, type checks — then report.

## 9. Bounded Iteration
If the same fix fails 3 times, STOP. Escalate with context: what you tried, what failed, what you think the problem is.

## 10. Ask Before High-Impact Changes
Adding dependencies, modifying schemas, changing public APIs, deleting shared files — pause and confirm before proceeding.
