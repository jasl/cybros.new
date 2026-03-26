# Core Matrix Architecture Health Audit Design

Use this design document before starting the first architecture-health audit
round for `core_matrix`.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-a-substrate-adjustments.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-b-provider-execution-foundation.md`
5. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
6. `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-design.md`
7. `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`
8. `core_matrix/docs/behavior/identifier-policy.md`

## Purpose

Run a repeatable architecture-health audit of `core_matrix` after the current
Phase 2 Milestone A through C batch.

This audit is not a bug-only review. It exists to find structural weakness in
the current system shape, including:

- responsibility drift across models, services, queries, and controllers
- contracts that are not orthogonal or have grown entangled
- logic that is correct but overly indirect, redundant, or hard to reason about
- concept and naming drift that makes the architecture harder to extend safely
- test shapes that reveal weak boundaries or awkward composition

The audit must also produce solutions, not only findings. Every confirmed
problem must include a practical corrective direction, and related problems
must be grouped into a larger unification proposal when they point at the same
non-orthogonal design.

## Why This Is A Separate Audit Mode

The existing `2026-03-26` review audit was intentionally defect- and
boundary-oriented. That was the right tool for:

- lifecycle and provenance regressions
- invalid boundary assumptions
- missed guard coverage
- correctness defects with direct production impact

This architecture-health audit uses a different lens. It asks whether the
current system shape is still healthy to evolve after multiple hardening passes,
even when the code is currently correct.

The audit therefore optimizes for:

- structural understanding before defect hunting
- broad signal collection from multiple viewpoints
- explicit distinction between confirmed findings and still-unproven signals
- a durable register that can survive multiple future rounds

## Scope

The first round is limited to `core_matrix`.

Primary review surfaces:

- `core_matrix/app/models`
- `core_matrix/app/services`
- `core_matrix/app/queries`
- `core_matrix/app/controllers`
- `core_matrix/test`

Secondary review surfaces, only when needed to confirm or reject a candidate:

- `core_matrix/config`
- `core_matrix/db`
- `core_matrix/docs/behavior`
- root-level `docs/plans` documents that define current phase intent

Out of scope for this audit mode:

- code changes or opportunistic fixes
- cross-project audit of `agents/fenix` or vendored gems
- product roadmap decisions outside the current Core Matrix architecture shape
- frontend or UI design review

## Audit Stance

The audit uses `structure-first review` as the primary mode and
`contract cross-check` as the secondary mode.

That means:

1. start by understanding the current system shape and ownership boundaries
2. identify where responsibilities, abstractions, and concepts are becoming
   sticky or unclear
3. use contracts such as timeline mutation, runtime binding, lineage,
   provider execution, and mailbox control to verify whether the suspected
   smell is real or is necessary complexity

This order matters. It prevents the audit from collapsing into a correctness
review that only finds already-visible bugs.

## Design Decisions

### 1. Use Parallel Broad Scans Followed By Main-Thread Review

The audit should not rely on a single sequential read path.

The first round will use several subagents to run broad, read-only sweeps from
different viewpoints. Their output is only a `candidate signal` list. The main
thread owns:

- de-duplication
- evidence review
- counterargument review
- clustering
- confidence assignment
- final report writing

Subagent output is never treated as a confirmed finding by itself.

### 2. Fix The Subagent Roles Up Front

The first round uses four viewpoints:

1. `Layering`
   Review whether responsibilities sit naturally across models, services,
   queries, and controllers.
2. `Contracts`
   Review whether timeline mutation, runtime binding, provider execution,
   lineage/provenance, and mailbox/control remain orthogonal.
3. `Complexity`
   Review large files, repeated guard templates, naming drift, local framework
   invention, and indirect logic.
4. `Test Reverse View`
   Review tests as evidence of production-code ergonomics, boundary quality,
   and composition cost.

This split is fixed so future rounds can compare like with like.

### 3. Force Subagent Output Into One Candidate Template

Each subagent candidate must use the same fields:

- `Candidate`
- `Category`
- `Why suspicious`
- `Evidence`
- `Possible impact`
- `Counterpoint`
- `Suggested direction`
- `Related concepts`

This keeps broad scans comparable and makes clustering possible later.

### 4. Require A Higher Evidence Bar For Confirmed Findings

The main thread can only promote a candidate into a confirmed finding when the
claim survives review from more than one angle.

Each confirmed finding must be backed by at least two of:

- direct code evidence
- comparison with sibling implementations
- test evidence or negative-path gaps
- conflict with an explicit behavior document or frozen root-shape contract

Signals that do not clear this threshold stay in the candidate pool.

### 5. Separate Priority From Confidence

The report uses two axes.

`Priority`

- `P0`: blocks safe evolution or keeps a critical boundary structurally brittle
- `P1`: does not block today, but is already increasing future cost or drift
- `P2`: worthwhile mid-term cleanup that will become more expensive later
- `P3`: localized hygiene issue with real but lower urgency

`Confidence`

- `High`: well-supported after main-thread review and counterpoint check
- `Medium`: likely real, but still missing one validating or falsifying angle
- `Low`: candidate signal only; useful for future rounds, not yet a conclusion

This split is mandatory. Do not mix certainty with importance.

### 6. Solutions Are Mandatory, Not Optional

Every confirmed finding must include:

- why the current shape is unhealthy
- a `local fix` direction
- a `systemic fix` direction when the problem is part of a wider pattern
- risks or tradeoffs if the proposed change is adopted

Do not publish findings that only criticize the current code.

### 7. Promote Related Findings Into Unification Opportunities

When several findings appear to be symptoms of the same architectural
non-orthogonality, the report must add an explicit `Unification Opportunity`.

Promote a cluster into that category when at least two of the following hold:

- the same rule is expressed in two or more namespaces
- the same concept appears to have multiple competing owners
- tests must take materially different setup paths to exercise one contract
- naming and concept placement have drifted enough that ownership is hard to
  infer from the code
- isolated local fixes would likely create or preserve duplicate logic

Each `Unification Opportunity` must describe:

- the current shape
- why the shape is not orthogonal
- the recommended target shape
- the single owner or source of truth
- what should be merged, deleted, or demoted to internal detail
- a plausible migration path

### 8. Preserve Healthy Patterns Explicitly

The audit must not become a one-way defect list.

Every round report must also call out healthy patterns worth preserving so that
future cleanup work does not accidentally remove good structure. This is
particularly important in `core_matrix`, where some complexity is real and tied
to durable kernel contracts.

### 9. Make Multi-Round State A First-Class Output

This audit is expected to run multiple times. The documentation model must
therefore separate stable method, cumulative register, and round-specific
observations.

Use three artifacts:

1. this design document
2. `docs/reports/core-matrix-architecture-health-audit-register.md`
3. `docs/reports/YYYY-MM-DD-core-matrix-architecture-health-audit-round-N.md`

The register carries stable identifiers and status across rounds. The round
report captures what changed in a specific run.

### 10. Distinguish Candidate Signals From Findings

Use these status concepts in the cumulative register:

- `candidate`
- `confirmed`
- `clustered`
- `unification-opportunity`
- `resolved`
- `retired`

This prevents every round from starting over and keeps unproven signals visible
without overstating them.

## Report Model

Each round report must include:

1. `Executive Summary`
2. `Confirmed Findings`
3. `Candidate Signals`
4. `Healthy Patterns Worth Preserving`
5. `Simplification / Reinforcement Backlog`
6. `Suggested Focus For The Next Round`

Each confirmed finding must include:

- title
- why it matters
- evidence
- counterpoint or limiting context
- related concepts
- local fix
- systemic fix or unification note
- priority
- confidence

The backlog is the translation layer from findings into next actions. It should
distinguish:

- candidates for simplification
- areas that need reinforcement or contract hardening
- items that should remain watch-list only for now

## First-Round Deliverables

The first round should produce:

1. a cumulative register at
   `docs/reports/core-matrix-architecture-health-audit-register.md`
2. a first round report at
   `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
3. a prioritized list of confirmed findings
4. a list of candidate-only signals worth revisiting
5. at least one explicit unification opportunity if the evidence supports it
6. a short list of healthy patterns worth preserving

## Completion Gate

Round 1 is only complete when all of the following are true:

- the four planned subagent broad scans have completed
- the main thread has de-duplicated and clustered their candidate output
- confirmed findings have been reviewed against code, adjacent implementations,
  and tests or docs where needed
- every confirmed finding includes a workable corrective direction
- every unification opportunity includes a target shape and migration path
- the register and round report both exist on disk
- the report clearly distinguishes confirmed findings from still-open signals
- the report includes healthy patterns, not only problems

## Non-Goals

This design intentionally does not:

- prescribe the exact findings that must exist before the audit starts
- assume that every broad scan signal will survive review
- require architectural unification where separate failure modes justify
  separate contracts
- turn the audit itself into an implementation batch

## Documentation Integrity Check

This design was reviewed for completeness on `2026-03-27`.

- the audit goal is explicit and distinct from the earlier defect-oriented audit
- the first-round scope is explicit and limited to `core_matrix`
- the subagent roles and candidate template are explicit
- the promotion rules from candidate to confirmed finding are explicit
- solutions and unification proposals are required output, not optional extras
- the multi-round documentation model is explicit
- the first-round deliverables and completion gate are explicit
- the design can be executed without inventing new process rules at runtime
