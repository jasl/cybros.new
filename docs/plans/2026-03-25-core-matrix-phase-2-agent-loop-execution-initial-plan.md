# Core Matrix Phase 2 Agent Loop Execution Initial Plan

**Goal:** Turn the phase-one substrate into a real `Core Matrix` agent loop that works through a mailbox-driven control plane, supports turn interruption plus conversation close semantics, and validates real provider, tool, subagent, and recovery behavior with `Fenix`.

## Status

Active execution baseline for the current Phase 2 plan set.

Phase 2 may take breaking changes freely:

- no backward-compatibility work is required for pre-phase-two experimental
  state
- no backfill or legacy-shape migration is required by default
- resetting the database is acceptable
- regenerating `schema.rb` is acceptable

## Architecture

Phase 2 keeps the kernel authoritative.

`Core Matrix` owns:

- workflow progression
- mailbox control delivery
- turn interrupt and close fences
- archive and delete orchestration
- conversation feature policy
- wait-state ownership
- capability governance
- recovery semantics

`Fenix` and other agent programs may own:

- prompt building
- runtime-stage hooks
- domain tools
- local retries inside one execution attempt
- skill execution

Durable side effects still flow back through kernel workflows.

## Protocol Direction

Phase 2 should assume:

- `mailbox / MQ + lease + deadlines` is the canonical control model
- `WebSocket` is preferred for low-latency control delivery
- `agent_poll` is a complete fallback path
- `message_retry`, `delivery_retry`, `step_retry`, `workflow_resume`,
  `workflow_retry`, and `close_escalation` are distinct concepts
- `turn_interrupt` is a reusable primitive, not a special case of archive or
  delete

## Formal Execution Units

Execute Phase 2 in this dependency order:

1. [2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md)
2. [2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md)
3. [2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md)
4. [2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md)
5. [2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md)
6. [2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md)
7. [2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md)
8. [2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md)
9. [2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md)
10. [2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md)
11. [2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md)
12. [2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md)
13. [2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md)
14. [2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md)

## Dependency Notes

- mailbox control must land before provider-backed execution and before archive
  or delete semantics
- conversation close semantics depend on the mailbox contract and on workflow
  substrate extensions
- provider-backed execution should consume the mailbox contract rather than
  discovering it ad hoc
- wait-state, subagent, and human-interaction work should build on the new
  retry and close-fence model
- proof export should finish before the final manual-acceptance task

## Validation Baseline

Phase 2 may assume:

- a mock LLM path exists for fast iteration
- a real provider path exists through current seeds and `.env`
- the OpenRouter credential can be materialized by `db:seed`
- bundled and external `Fenix` runs are available for validation

## Out Of Scope

- Web UI productization
- workspace-owned trigger and delivery infrastructure
- IM, PWA, or desktop channels
- extension or plugin packaging
- kernel-owned prompt building
- kernel-owned universal compaction or summarization
