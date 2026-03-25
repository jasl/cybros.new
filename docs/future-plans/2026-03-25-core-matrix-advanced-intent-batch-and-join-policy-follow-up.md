# Core Matrix Advanced Intent Batch And Join Policy Follow-Up

## Status

Deferred follow-up for workflow-first execution beyond the narrow Phase 2
intent-batch model.

## Purpose

Phase 2 should prove workflow-first yield and resume with a small surface.

This follow-up tracks capabilities that are intentionally deferred so the Phase
2 core design stays small and verifiable.

## Deferred Capabilities

- `completion_barrier = wait_any`
- `completion_barrier = quorum(n)`
- `completion_barrier = all_settled`
- automatic continuation of an interrupted batch tail
- broader parallel intent allowlists beyond the initial Phase 2 set
- detached long-running child execution that continues without a successor
  agent re-entry point
- richer batch-level recovery policy beyond `resume_policy = re_enter_agent`

## Why Deferred

These features are valuable, but they widen the state machine considerably:

- more join policies create more recovery and proof combinations
- automatic tail continuation risks reusing outdated execution assumptions
- broad parallelism increases conflict-scope, audit, and visualization
  complexity

They should be reconsidered only after the narrow Phase 2 model has passed real
manual validation.

## Activation Trigger

Re-open this follow-up when all of the following are true:

- workflow-first yield and resume is proven in real Phase 2 runs
- successor `AgentTaskRun` re-entry is stable
- the Mermaid proof artifacts remain readable under the current graph shape
- there is a concrete product need for richer join policy or broader automatic
  parallelism

## Related Documents

- [2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md)
- [2026-03-25-core-matrix-phase-2-agent-loop-execution-follow-up.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-follow-up.md)
