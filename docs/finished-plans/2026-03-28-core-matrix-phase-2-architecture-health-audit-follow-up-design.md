# Core Matrix Phase 2 Design: Architecture Health Audit Follow-Up

Use this design document before starting the Milestone C follow-up batch that
audits the current architecture health of `core_matrix`.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
5. `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-design.md`
6. `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`
7. `docs/plans/2026-03-27-core-matrix-architecture-health-audit-design.md`
8. `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
9. `core_matrix/docs/behavior/workflow-graph-foundations.md`
10. `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
11. `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
12. `core_matrix/docs/behavior/provider-governance-models-and-services.md`
13. `core_matrix/docs/behavior/identifier-policy.md`

## Purpose

Run one broad, architecture-first audit of the current `core_matrix` system
shape after the Milestone A through C batch and its later hardening follow-ups.

This audit is not a repeat of the earlier correctness-heavy review work. The
goal is to answer a different question:

- is the current Core Matrix architecture still healthy to evolve
- where is the complexity necessary and intentional
- where is the complexity starting to become accidental, redundant, or
  non-orthogonal
- which structural issues or simplification opportunities are worth acting on
  next

## Why This Follow-Up Exists

The recent Phase 2 work has already been audited several times for concrete
defects, contract regressions, and lifecycle safety gaps. That has real value,
but it leaves a separate question unanswered:

- after all of those fixes, is the whole system still shaped well

This follow-up exists because the answer can no longer come from reading only
the newest files or only the hardest Phase 2 paths. The whole `core_matrix`
application needs one deliberate architecture-health pass.

This design also intentionally differs from
`2026-03-27-core-matrix-architecture-health-audit-design.md`.

That earlier document described a durable multi-round audit campaign with a
register and round reports. This follow-up is narrower and more immediate:

- it lands as a Milestone C follow-up
- it audits the whole current `core_matrix` codebase in one focused batch
- it writes one actionable findings artifact instead of standing up a long-lived
  audit register
- it keeps only the results that are worth acting on, plus the short system
  judgment needed to prioritize next work

## Scope

Primary review surfaces:

- `core_matrix/app/models`
- `core_matrix/app/services`
- `core_matrix/app/queries`
- `core_matrix/app/controllers`
- `core_matrix/test`

Secondary review surfaces, used only when needed to confirm or reject a
candidate conclusion:

- `core_matrix/docs/behavior`
- `core_matrix/config`
- `core_matrix/db`
- root-level `docs/plans` documents that freeze current phase intent

Out of scope:

- opportunistic code fixes during the audit itself
- cross-project audit of `agents/fenix`
- vendored gem review
- frontend or browser-surface review
- roadmap invention beyond architecture findings and next-step priority

## System Map For This Audit

This audit treats `core_matrix` as six interacting boundaries rather than as a
directory tree.

### 1. Conversation And Lifecycle

- `Conversation`
- `Turn`
- archive, delete, close, lineage, and mutation contracts

### 2. Workflow And Execution Graph

- `WorkflowRun`
- workflow graph mutation
- scheduler, wait states, retry, and resume

### 3. Runtime Control Plane

- `agent_control`
- mailbox delivery
- report ingestion
- freshness, close, and reconciliation paths

### 4. Runtime Binding And Deployments

- `ExecutionEnvironment`
- `AgentDeployment`
- deployment recovery, rebinding, rotation, and health

### 5. Provider And Governance

- provider catalog
- credential, entitlement, and policy governance
- provider execution

### 6. Read Side And Projection

- queries
- runtime resource APIs
- publication and operator-facing projection surfaces

Each boundary is reviewed with the same questions:

- what is the single authority for this concept
- where is state written and re-written
- is the ownership readable from names and placement
- are sibling flows reusing one contract or hand-copying one another
- is the test shape reinforcing the boundary or compensating for a weak one

## Decisions

### 1. Audit The Whole Current `core_matrix`, Not Only Phase 2 Hotspots

Phase 2 surfaces remain high-yield review targets, but they are not the whole
scope. This audit must inspect the full current architecture so cross-boundary
drift is not missed.

### 2. Use A Boundary-First Review Model

The audit does not proceed directory by directory. It proceeds boundary by
boundary across the six system areas listed above.

That keeps the review aligned with architectural questions such as:

- who owns runtime identity
- who owns lifecycle progression
- where provider decisions end and execution begins
- where read-side projection stops and domain mutation starts

### 3. Use Two Different Passes

The audit runs in two passes.

Pass A: boundary review

- inspect the six system boundaries
- identify authority drift, split lifecycle writers, concept overlap, and local
  reinvention

Pass B: anti-pattern cross-check

- re-scan the system for repeated guard, lock, transaction, payload, and naming
  patterns
- compare sibling implementations and test shapes
- keep only the conclusions that still hold after the second angle

The second pass is required. The report must not depend on first-read
impressions alone.

### 4. The Output Stays Narrow

The final artifact keeps only two result categories:

- `Findings`
- `Simplification / Reinforcement Opportunities`

This follow-up intentionally does not produce a broad catalog of healthy
patterns or weak candidate signals. The user explicitly wants the audit to stay
actionable and selective.

### 5. Evidence Must Clear A Concrete Threshold

Nothing enters the final artifact unless it:

- points to specific files and call paths
- explains why the issue is structural rather than stylistic preference
- identifies the maintenance, reasoning, or correctness cost of the current
  shape
- names a concrete direction such as delete, merge, extract, centralize,
  downscope, or reinforce with tests and contract docs

Low-confidence smells stay out of the final artifact.

### 6. The Audit Must End With A System-Level Judgment

The final report must not stop at a list of local observations. It must answer:

- whether the current architecture is broadly healthy
- where the system's necessary complexity is concentrated
- where accidental complexity has started to form
- which three structural priorities deserve the next follow-up batch

### 7. This Batch Belongs To Milestone C Follow-Up Work

This audit lands as a new Milestone C follow-up because the current system
shape was materially created by Milestone C and its later hardening passes:

- runtime pairing
- mailbox control
- close reconciliation
- runtime binding
- mutation safety
- lineage and provenance hardening

The findings should therefore feed the next Milestone C structural cleanup
batch rather than becoming a disconnected side path.

## Expected Deliverable

The execution plan created from this design must produce one findings document
at:

- `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`

That artifact must include:

- scope summary
- short system judgment
- ordered findings
- ordered simplification and reinforcement opportunities
- the three highest-value structural next steps
- a completeness check that confirms coverage and evidence quality

## Completion Gate

Do not consider this follow-up complete until all of the following are true:

- the whole current `core_matrix` architecture has been reviewed through the
  six-boundary model
- the anti-pattern cross-check has been run after the main boundary pass
- every reported item includes evidence and an action direction
- the final artifact distinguishes findings from simplification opportunities
- the final artifact ends with a short system-level judgment and three next
  priorities
- the written result is complete enough that a later implementation plan can be
  created without rediscovering the architecture questions from scratch

## Documentation Integrity Check

This design is only valid if all of the following remain true:

- the scope is the whole current `core_matrix` application
- the review method is boundary-first plus anti-pattern cross-check
- the output remains intentionally selective
- the audit stays tied to Milestone C follow-up work
- the deliverable is one actionable findings artifact, not a long-lived audit
  register
