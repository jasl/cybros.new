# Superseded: Core Matrix Phase 2 Sequential Execution Design

## Status

Superseded on `2026-03-30` by:

- [2026-03-30-core-matrix-phase-2-follow-up-node-execution-and-dag-merge-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-30-core-matrix-phase-2-follow-up-node-execution-and-dag-merge-plan.md)

## Why This Was Replaced

The earlier sequential package assumed Phase 2 should be executed and reasoned
about as a workflow-wide or milestone-sequential unit. That is no longer the
design.

Current Phase 2 execution rules are:

- `WorkflowNode` is the async execution boundary
- `WorkflowEdge.requirement = required | optional` is the first-pass merge
  contract
- merge nodes are one-shot and do not retrigger on late optional predecessor
  completion
- one runnable node maps to one node job; `WorkflowRun` is not the async unit

Keep this file only as a historical pointer. Do not use it to guide active
implementation or acceptance work.
