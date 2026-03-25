# Core Matrix Workflow Yield And Intent Batch Design

## Status

Approved focused design note for workflow-first agent cooperation in Phase 2.

This document narrows one question only: how `AgentTaskRun` should yield
kernel-governed intentions into workflow-owned execution without collapsing the
workflow model into ad hoc side effects.

## Purpose

Use this document to define:

- the workflow-first yield and resume rule for `AgentTaskRun`
- how kernel-governed intents are batched and materialized
- which Phase 2 batch and parallelism features are in scope
- how workflow visualization and proof should validate the behavior

## Decision Summary

- Any agent action that crosses into `Core Matrix` must become workflow-managed
  execution rather than an in-place side effect.
- `AgentTaskRun` yields `IntentBatch` payloads rather than mutating kernel state
  directly.
- Phase 2 `IntentBatch` uses ordered `stages[]`, not one flat unstructured list
  and not a fully arbitrary coroutine graph.
- Phase 2 supports:
  - `dispatch_mode = serial`
  - `dispatch_mode = parallel`
  - `completion_barrier = none`
  - `completion_barrier = wait_all`
- Accepted intents materialize as `WorkflowNode` rows and, when needed,
  workflow-owned runtime resources.
- Rejected intents remain workflow-visible through `WorkflowNodeEvent` and
  audit, but do not need their own mutation node.
- Phase 2 resume policy should be `re_enter_agent`, not automatic continuation
  of an old batch tail under a stale snapshot.
- Phase 2 parallel intent kinds should begin narrowly with:
  - `conversation_title_update`
  - `subagent_spawn`
- Workflow visualization and proof artifacts are part of Phase 2 acceptance, not
  optional debugging extras.

## Why Workflow-First Yield Is Required

If an accepted intent can mutate kernel-owned state while the current
`AgentTaskRun` continues in place, then the runtime risks crossing a frozen
execution snapshot, feature-policy snapshot, capability binding snapshot, or
tail guard with mutated world state.

That is the wrong boundary.

The correct rule is:

- once the runtime asks `Core Matrix` to do something durable, it has reached a
  workflow yield point
- the kernel materializes that request through workflow-owned execution
- any later agent continuation happens through a successor `AgentTaskRun` with
  a refreshed snapshot

## Intent Batch Model

Recommended conceptual object:

- `IntentBatch`

Recommended durable storage shape in Phase 2:

- one `WorkflowArtifact(intent_batch_manifest)` attached to the yielding
  workflow node
- `WorkflowNodeEvent` rows for batch request, stage progress, rejection, block,
  and completion facts

Recommended manifest fields:

- `batch_id`
- `resume_policy`
- `stages`
- `requested_at`
- `yielding_execution_id`

Recommended stage fields:

- `stage_index`
- `dispatch_mode`
- `completion_barrier`
- `intents`

Recommended intent fields:

- `intent_id`
- `intent_kind`
- `requirement`
- `conflict_scope`
- `payload`
- `idempotency_key`

## Phase 2 Stage Semantics

### Dispatch Modes

- `serial`
  one intent at a time, in order
- `parallel`
  multiple intents in the same stage may be materialized concurrently when the
  kernel allows that combination

### Completion Barriers

- `none`
  the parent workflow does not wait for later child completion beyond the
  immediate materialization result of the stage
- `wait_all`
  the parent workflow waits until all blocking children in the stage reach the
  required join point before a successor agent step may continue

### Intent Requirement

- `required`
  a blocking, rejected, or failed intent stops forward execution at that stage
- `best_effort`
  a rejected or failed intent is recorded, but the stage may continue when
  policy allows

## Materialization Rules

Accepted intents should materialize as one of:

- `WorkflowNode` only
- `WorkflowNode + workflow-owned runtime resource`

Examples:

- `conversation_title_update`
  materializes one terminal workflow node
- `context_compaction_persist`
  materializes one workflow node and writes or supersedes
  `ConversationSummarySegment`
- `human_interaction_request`
  materializes one workflow node plus `HumanInteractionRequest`
- `subagent_spawn`
  materializes one workflow node plus `SubagentRun`

Rejected intents should:

- append `WorkflowNodeEvent` on the yielding node or current batch trace
- record machine-readable rejection reason
- participate in audit and proof output
- not silently disappear

## Resume Rules

Phase 2 should keep resume semantics simple and safe.

Recommended rule:

- `resume_policy = re_enter_agent`

That means:

- if a batch blocks or stops on a required failure, the kernel records the
  batch outcome and the stopping point
- after wait or recovery resolution, the scheduler creates a successor
  `AgentTaskRun`
- the successor sees a refreshed snapshot plus the prior batch outcome summary
- the kernel does not auto-run the untouched tail of the older batch

## Parallelism Guardrails

Parallel dispatch must stay kernel-authorized.

Phase 2 rules:

- each intent kind declares whether it is parallelizable
- each intent kind declares a `conflict_scope`
- the kernel rejects or serializes a parallel stage when conflict scopes are
  incompatible
- Phase 2 should begin with a narrow allowlist:
  - `conversation_title_update`
  - `subagent_spawn`

Rationale:

- title updates are low-risk metadata mutations that can be best-effort and
  terminal
- subagent spawns are the clearest first case of useful bounded parallelism

## Failure And Blocking Behavior

Phase 2 should use ordered prefix-commit semantics.

Rules:

- accepted durable prefixes remain durable
- a required rejection, required failure, or blocking barrier stops forward
  execution at that point
- later stages do not auto-run under the old snapshot
- best-effort intents may fail terminally without blocking the workflow when
  their stage and policy allow it

This is intentionally not an all-or-nothing database transaction across the
whole batch.

## Visualization And Proof

Phase 2 should add a workflow-level Mermaid exporter for validation and manual
proof.

Recommended scope:

- export `WorkflowRun`, `WorkflowNode`, and workflow edges
- summarize selected batch and wait facts from `WorkflowNodeEvent`
- keep the graph readable rather than rendering every event as a node

Proof artifacts should include at least:

- scenario name
- run count
- workflow node and edge counts
- Mermaid output path
- note about blocking resources, yield points, or successor agent steps

Minimum proof scenarios:

- `agent_turn_step -> context_compaction_persist -> successor agent_turn_step`
- `agent_turn_step -> conversation_title_update -> successor agent_turn_step`
- `agent_turn_step -> parallel subagent stage -> wait -> successor agent_turn_step`

## Phase 2 Non-Goals

This design does not require Phase 2 to ship:

- `wait_any`
- `quorum(n)`
- `all_settled`
- automatic continuation of a stopped batch tail
- broad parallelism for arbitrary intent kinds
- a free-form coroutine graph inside one workflow run

Those belong in a follow-up once the narrow workflow-first execution model is
proven.

## Related Documents

- [2026-03-25-core-matrix-agent-execution-delivery-contract-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md)
- [2026-03-25-core-matrix-platform-phases-and-validation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md)
- [2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md)
- [2026-03-25-core-matrix-advanced-intent-batch-and-join-policy-follow-up.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-advanced-intent-batch-and-join-policy-follow-up.md)
