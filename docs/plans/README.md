# Plans Index

This directory contains the active execution plans for `core_matrix`.

`Phase 2` is still active, but Milestones A through C and their completed
follow-ups are now archived under `docs/finished-plans`.

## Current Code Scan Summary (`2026-03-30`)

- `Task D1` is partially landed. During-generation `reject`, `restart`, and
  `queue` behavior plus stale-tail guards already exist, but persisted
  conversation feature policy and feature snapshots on active work do not.
- `Task D2` is partially landed. Human-interaction services, subagent spawn,
  wait-state persistence, and bounded `wait_all` batch artifacts already exist,
  but yielded runtime requests are not yet wired into a full end-to-end
  workflow-owned wait/subagent handoff.
- `Task E1` still needs the durable governance model. Capability snapshots and
  effective tool-catalog composition exist, but `ToolBinding`,
  `ToolInvocation`, and related audited binding-freeze records do not.
- `Task E2` remains greenfield after the current scan.
- `Task F1` remains greenfield in `agents/fenix`; the repo currently has no
  skill directories or skill-surface services/tests.
- `Task F2` remains unimplemented beyond the committed
  `docs/reports/phase-2/` artifact scaffolding.
- `Task F3` remains blocked on the unfinished D/E/F execution work.

## Active Entry Points

- [2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md)
- [2026-03-30-core-matrix-phase-2-milestone-d-sequential-execution-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-core-matrix-phase-2-milestone-d-sequential-execution-plan.md)
- [2026-03-30-core-matrix-phase-2-milestone-e-sequential-execution-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-core-matrix-phase-2-milestone-e-sequential-execution-plan.md)
- [2026-03-30-core-matrix-phase-2-milestone-f-sequential-execution-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-core-matrix-phase-2-milestone-f-sequential-execution-plan.md)
- [2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md)
- [2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md)
- [2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md)
- [2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md)
- [2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md)
- [2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md)
- [2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md)

## Active Execution Order

1. `Task D1` remaining feature-policy work
2. `Task D2` remaining yield-owned wait and subagent orchestration
3. `Task E1`
4. `Task E2`
5. `Task F1`
6. `Task F2`
7. `Task F3`

## Completed Phase 2 Archives

- `Milestone A`:
  [2026-03-26-core-matrix-phase-2-milestone-a-substrate-adjustments.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-26-core-matrix-phase-2-milestone-a-substrate-adjustments.md)
- `Milestone B`:
  [2026-03-26-core-matrix-phase-2-milestone-b-provider-execution-foundation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-26-core-matrix-phase-2-milestone-b-provider-execution-foundation.md)
- `Milestone C`:
  [2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md)
- `Close State Consolidation`:
  [2026-03-29-core-matrix-phase-2-plan-subagent-session-close-state-model-consolidation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-29-core-matrix-phase-2-plan-subagent-session-close-state-model-consolidation.md)

Use the phase plan for active ordering. Use the archived milestone records for
historical implementation context that has already passed acceptance.
