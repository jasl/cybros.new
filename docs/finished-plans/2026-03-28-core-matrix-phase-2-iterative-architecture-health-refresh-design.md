# Core Matrix Phase 2 Design: Iterative Architecture Health Refresh Audit

Use this design document before starting the next architecture-health audit of
`core_matrix`.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-design.md`
4. `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`
5. `docs/plans/2026-03-28-core-matrix-phase-2-plan-structural-consolidation-follow-up.md`
6. `docs/plans/2026-03-28-core-matrix-phase-2-plan-post-consolidation-repair-loop.md`
7. `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
8. `core_matrix/docs/behavior/subagent-sessions-and-execution-leases.md`
9. `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
10. `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
11. `core_matrix/docs/behavior/agent-runtime-resource-apis.md`

## Purpose

Run a refreshed architecture-health audit of the whole current `core_matrix`
system while Phase 2 is still mid-flight and destructive cleanup is still
cheap.

This audit answers a narrower and more urgent question than the earlier
follow-up:

- after the previous audit, structural consolidation, repair-loop work, and
  conversation-first subagent-session changes, what structural problems still
  remain
- which earlier concerns have actually been resolved
- what new high-confidence risks have appeared around the newest Phase 2
  boundaries
- which issues should be fixed now, before more Phase 2 features accumulate on
  top of them

## Why This Audit Exists

The repository already contains one architecture-health audit and two later
cleanup plans. That is useful context, but it is not enough to answer the
current question.

The system shape has moved since then:

- provider execution has already been split once
- deployment recovery has already been refactored once
- lifecycle and mutation contracts have already been partially consolidated
- `SubagentSession` and conversation-first delegation are now first-class
  architecture, not proposed future shape

That means a good new audit must do two things at once:

- reuse the earlier audit as a set of tested hypotheses
- re-scan the current codebase independently enough to catch fresh issues and
  avoid repeating stale conclusions

## Scope

Primary review surface:

- whole current `core_matrix`

Primary directories:

- `core_matrix/app/models`
- `core_matrix/app/services`
- `core_matrix/app/queries`
- `core_matrix/app/controllers`
- `core_matrix/test`

Focused hotspot surfaces inside that whole-system audit:

- conversation and lifecycle contracts
- workflow and execution graph contracts
- runtime control and close reconciliation
- runtime capability composition and projection
- execution snapshot shaping
- `SubagentSession` ownership and delegation flows
- `core_matrix <-> agents/fenix` responsibility boundaries

Secondary references, used only to confirm or reject a candidate conclusion:

- `core_matrix/docs/behavior`
- root-level Phase 2 planning documents
- `agents/fenix` runtime manifest and execution-context code, but only as the
  external boundary of `core_matrix`

Out of scope:

- full independent architecture audit of `agents/fenix`
- opportunistic code fixes during the audit itself
- vendored gem review
- frontend review
- compatibility-preserving migration design

## Audit Shape

### 1. Mixed Refresh Model

This audit is neither a pure re-run nor a pure from-scratch review.

It uses a mixed refresh model:

- treat the earlier architecture-health findings as known hypotheses
- verify which earlier findings are still true in the current code
- identify which earlier concerns have already been resolved by consolidation
  work
- re-scan the whole system to find new high-confidence issues that did not
  exist, or were not visible, in the earlier audit

Final reporting must distinguish:

- earlier finding still present
- earlier finding materially resolved
- newly discovered issue
- newly discovered risk smell or preemptive warning

### 2. Whole-System Review With Hotspot Deep Dives

The audit still covers the whole current `core_matrix`; it does not narrow
itself to only the latest Phase 2 files.

However, some surfaces deserve deeper review because they are both new and
structurally central:

- `SubagentSession`
- runtime capability composition
- close and reconcile control
- execution snapshots
- `core_matrix <-> fenix` handoff contracts

### 3. Evidence-First Results

The output must stay selective.

Only two result families are allowed:

- `Confirmed Findings`
- `Risk Smells / Reinforcement Opportunities`

Everything reported must point to concrete code and name the structural cost of
the current shape.

## Evidence Bar

An item may enter `Confirmed Findings` only if all of the following are true:

- it points to concrete files, classes, methods, or call paths
- the issue is structural, not merely stylistic
- it names a concrete cost such as reasoning drift, duplicate authority,
  unnecessary orchestration growth, leaky contracts, testing fragility, or
  boundary confusion
- it survives at least one counter-check against neighboring code, tests, or
  behavior docs
- it includes an action direction such as delete, merge, centralize, split,
  contract, or reinforce

An item may enter `Risk Smells / Reinforcement Opportunities` only if:

- it is not yet a confirmed defect or architectural break
- it shows a clear growth trend toward accidental complexity
- it is specific enough that later work can deliberately prevent that trend

Do not publish:

- naming preferences without structural consequence
- style-only complaints
- low-confidence suspicions that were not counter-checked
- earlier findings that no longer hold in the current code

## Priority Model

Every reported item should be assigned one of three practical priorities:

1. `Act Now`
   - the current structure is already bad enough that more Phase 2 work is
     likely to compound it
2. `Good Mid-Phase Cleanup`
   - the issue is worth fixing while destructive change is still cheap, even if
     it is not yet blocking
3. `Watch Closely`
   - the shape is still tolerable, but it should be called out now so later
     work does not accidentally harden it into a real problem

## Iterative Scan Model

This audit must use iterative scan loops instead of a single linear read pass.

The minimum scan structure is:

### Round 1: Baseline Reconciliation

- capture the current architecture map
- compare the current code against the earlier audit and follow-up plans
- mark earlier issues as resolved, residual, or uncertain

### Round 2: Boundary Review

Re-scan the system through the main architecture boundaries:

- conversation and lifecycle
- workflow and execution graph
- runtime control plane
- runtime binding and deployments
- provider and governance
- read side and projection

### Round 3: Hotspot Deep Dive

Deep-read the newest and most sensitive surfaces:

- `SubagentSession`
- runtime capability composition
- close and reconcile flows
- execution snapshots
- `core_matrix <-> fenix` responsibility boundaries

### Round 4: Cross-Cut Anti-Pattern Pass

Re-scan for repeated structural patterns rather than business boundaries:

- guard-family duplication
- lock and transaction duplication
- raw-hash contract spread
- duplicate wrapper and adapter layers
- orchestration hotspots
- naming or concept drift

### Round 5: Counter-Evidence Pass

- use tests, docs, and sibling implementations to challenge candidate findings
- remove any item that now looks like intentional design or already-resolved
  structure
- only promote survivors into the final report

## Loop Rule

The audit does not stop after the fifth round automatically.

If a round discovers any new high-confidence issue, run another round focused
on the neighboring boundary or contract family until the system stops yielding
new concrete findings.

Stop only when both conditions hold:

- at least five rounds have been completed
- two consecutive rounds produce no new high-confidence findings

## Required Internal Tracking

During execution, maintain a private audit register for each round with:

- new candidate findings
- candidates rejected by counter-evidence
- candidates still pending validation
- whether the item looks like earlier residual drift or a new issue

That private register is scratch material only. It should inform the final
report, but it does not become a committed artifact.

## Expected Deliverable

The implementation plan created from this design must produce one refreshed
audit document under `docs/plans/` that includes:

- scope summary
- system judgment
- confirmed findings
- risk smells or reinforcement opportunities
- distinction between residual earlier issues and newly discovered issues
- three structural priorities for immediate follow-up
- a completeness check that states how many rounds were run and why the audit
  stopped

## Completion Gate

Do not consider this audit complete until all of the following are true:

- the whole current `core_matrix` codebase has been reviewed
- `agents/fenix` has been checked as an external boundary of `core_matrix`
- the earlier audit and follow-up plans have been explicitly reconciled against
  current code
- at least five rounds were run
- two consecutive rounds produced no new high-confidence findings
- every published item clears the evidence bar
- the final report clearly separates confirmed issues from risk smells
- the final report clearly separates earlier residual issues from newly
  discovered issues
- the final report ends with exactly three immediate structural priorities

## Documentation Integrity Check

This design is valid only if all of the following remain true:

- the audit remains whole-system, not hotspot-only
- iterative scanning remains mandatory
- destructive cleanup remains an acceptable future response to the findings
- the report stays selective and evidence-backed rather than becoming a broad
  diary of impressions
