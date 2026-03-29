# Core Matrix Phase 2 Sequential Execution Design

## Status

Active execution-control design for the remaining Phase 2 implementation batch.

## Purpose

The existing Phase 2 task documents define scope and technical targets, but
they do not yet define a strong enough operator contract for a long-running,
mostly unattended implementation pass.

This design freezes that operator contract for the remaining work:

- execute strictly in milestone order: `D -> E -> F`
- use the current workspace only; do not create a worktree for this batch
- stop immediately on unresolved blockers instead of guessing
- treat destructive correction as acceptable when it improves Phase 2 quality
- keep manual validation and proof capture as first-class acceptance work

## Source Of Truth Split

Use the documents in this order:

1. `AGENTS.md`
2. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
3. this design document
4. the milestone execution plan for the active batch
5. the detailed task documents for the active milestone
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Interpretation rules:

- the phase plan remains the authoritative scope and milestone-order index
- the detailed task docs remain the authoritative feature-level source of truth
- the milestone execution plans define unattended sequencing, stop rules, and
  verification gates
- the checklist is the authoritative manual-validation ledger and must be kept
  current before final acceptance starts

## Execution Mode

This batch should run under the following execution assumptions:

- current repository workspace only
- current branch or a newly created branch is allowed
- no worktree
- sequential execution only; do not start Milestone `E` before Milestone `D`
  has passed its exit gate, and do not start `F` before `E` has passed
- user may be away from the keyboard; continue automatically only while the
  current task, architecture, and verification outcome remain unambiguous

## Change Policy

Retained Phase 2 change policy:

- breaking changes are allowed
- compatibility with earlier experimental state is not required
- old migrations may be edited in place
- `schema.rb` should be regenerated after schema changes
- database reset is acceptable
- legacy-shape rejection or compatibility tests are out of scope

## Mandatory Stop Rules

Stop and ask for direction immediately when any of the following happens:

- the active task document conflicts with current code in a way that changes
  product semantics instead of implementation detail
- the next step would require inventing or guessing behavior not stated in the
  current plans or design docs
- a real external dependency is required for truthful validation and is missing
  or misconfigured
- automated verification and observed runtime behavior disagree
- the most plausible fix would require broad architectural deviation from the
  frozen Phase 2 roots
- the active migration or schema strategy becomes ambiguous enough that the
  resulting data model could plausibly be wrong

Do not continue past these conditions by local guesswork.

## Preflight Gates

Each milestone begins with a preflight gate.

### Milestone D Preflight

Confirm:

- no persisted conversation feature policy or frozen feature snapshot model has
  already appeared unexpectedly
- the existing wait-state and subagent substrate still matches the status
  refresh recorded in the active plans
- the targeted D1 and D2 tests fail for the expected reasons before new code is
  written

### Milestone E Preflight

Confirm:

- the D milestone exit criteria are satisfied
- there is still no conflicting durable governance model in place
- the intended real MCP validation path is concrete enough to test under
  `bin/dev` later

### Milestone F Preflight

Confirm:

- D and E exit criteria are satisfied
- the manual validation checklist already enumerates every required Phase 2
  acceptance scenario
- proof-export and README status work can be completed without inventing new
  product semantics

## Verification Model

Every milestone must produce all of the following before it is considered done:

1. targeted red-green verification for the milestone's task set
2. integrated milestone-level automated verification
3. doc updates for any retained behavior that changed materially
4. checklist updates for any new manual path the milestone introduces

Milestone `F` additionally requires:

5. real `bin/dev` manual validation using the refreshed checklist
6. proof artifact capture under `docs/reports/phase-2/`
7. final code and documentation audit before Phase 2 is declared ready for user
   acceptance

## Manual Validation Authority

`docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md` is the
single manual-validation source of truth for this batch.

Rules:

- add or refresh required Phase 2 scenarios in the checklist before final
  manual testing starts
- when a milestone creates a new manual path, update the checklist as part of
  that same milestone instead of leaving the operator flow implicit
- during final acceptance, execute the checklist in order and record concrete
  identifiers, observed DAG shape, and conversation-state results

## Required Final Evidence

The full batch is not ready for user acceptance until it can provide:

- passing milestone-targeted automated verification
- passing project-level verification across `core_matrix`,
  `core_matrix/vendor/simple_inference`, and `agents/fenix`
- real-environment validation for bundled and external `Fenix`
- real provider-backed loop evidence
- real human-interaction, subagent, `process_run`, governed tool, and governed
  MCP evidence
- workflow proof packages committed under `docs/reports/phase-2/`
- README and behavior-doc status aligned with the code actually shipped

## Non-Goals

- allowing execution to skip milestone order for convenience
- preserving compatibility with pre-Phase-2 experimental data shapes
- replacing manual validation with UI automation
- treating final acceptance as only an automated test run

## Related Documents

- [2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md)
- [2026-03-30-core-matrix-phase-2-milestone-d-sequential-execution-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-core-matrix-phase-2-milestone-d-sequential-execution-plan.md)
- [2026-03-30-core-matrix-phase-2-milestone-e-sequential-execution-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-core-matrix-phase-2-milestone-e-sequential-execution-plan.md)
- [2026-03-30-core-matrix-phase-2-milestone-f-sequential-execution-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-core-matrix-phase-2-milestone-f-sequential-execution-plan.md)
- [2026-03-24-core-matrix-kernel-manual-validation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md)
