# Core Matrix Phase 2 Plan: Agent Loop Execution

## Status

Active phase-level plan for the remaining post-Milestone-C breadth and
validation phase.

## Purpose

Phase 2 proves that `Core Matrix` can run a real agent loop end to end under
kernel authority, including mailbox-driven control, turn interruption,
conversation close semantics, governed capability use, and real runtime
validation with `Fenix`.

## Phase 2 Change Policy

Phase 2 should optimize for architectural correction, not compatibility.

Rules:

- breaking changes are allowed
- no backward-compatibility work is required for pre-phase-two experimental
  state
- no data backfill or legacy-shape migration is required unless it directly
  reduces current implementation risk
- resetting the database is acceptable
- regenerating `schema.rb` is acceptable
- Phase 1 mock-LLM helpers and `core_matrix/vendor/simple_inference` may take
  breaking changes freely when that reduces Phase 2 implementation risk

Frozen substrate assumptions for this phase:

- `Conversation -> Turn -> WorkflowRun -> WorkflowNode` is the authoritative
  execution root chain
- `AgentInstallation -> ExecutionEnvironment -> AgentDeployment` is the
  authoritative runtime lineage for Phase 2 follow-up work
- agent capability snapshots remain deployment-scoped, while environment
  capability state is first-class on `ExecutionEnvironment`
- capability publication must materialize `agent_plane`,
  `environment_plane`, and `effective_tool_catalog`
- Phase 2 work should extend those roots instead of introducing parallel pause,
  close, delivery, or projection ledgers for the same facts
- workflow wait, retry, and close control should reuse workflow-owned durable
  state rather than inventing task-local shadow stores

## Related Design And Research

- [2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md)
- [2026-03-25-core-matrix-platform-phases-and-validation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md)
- [2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md)
- [2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md)
- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)
- [2026-03-26-core-matrix-phase-2-execution-environment-and-agent-runtime-boundary-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-26-core-matrix-phase-2-execution-environment-and-agent-runtime-boundary-design.md)
- [2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)
- [2026-03-25-fenix-phase-2-validation-and-skills-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md)

## Current Implementation Milestones

Milestones A through C and their appended hardening or audit follow-ups are
complete and archived under `docs/finished-plans`.

The current implementation focus should now continue with the later breadth and
validation milestones.

## Status Refresh (`2026-03-30`)

Current code scan summary:

- `Task D1` is partially landed.
  Current code already proves during-generation `reject`, `restart`, and
  `queue` handling plus stale queued-tail cancellation, but it does not yet
  persist a conversation feature policy or freeze feature snapshots onto active
  work.
- `Task D2` is partially landed.
  Current code already includes workflow wait-state storage,
  `HumanInteractions::*`, `SubagentSessions::*`, `Workflows::ManualResume`,
  and `IntentBatchMaterialization`, but the runtime-to-kernel handoff from
  yielded agent requests into those workflow-owned resources is still missing.
- `Task E1` still lacks the durable governance layer.
  `CapabilitySnapshot`, `RuntimeCapabilityContract`, and effective tool-catalog
  composition are in place, but the planned `ToolDefinition`,
  `ToolImplementation`, `ToolBinding`, and `ToolInvocation` model boundary is
  not.
- `Task E2` is still greenfield after the current scan.
- `Task F1` is still greenfield inside `agents/fenix`.
- `Task F2` and `Task F3` still depend on unfinished D/E/F behavior, although
  `docs/reports/phase-2/` has already been created as the acceptance-artifact
  root.

## Active Execution Order

The active unattended execution batch for the current phase is:

1. `Task D1` remaining feature-policy and feature-snapshot work
2. `Task D2` remaining yield-owned wait and subagent orchestration
3. `Task E1`
4. `Task E2`
5. `Task F1`
6. `Task F2`
7. `Task F3`

## Sequential Execution Package (`2026-03-30`)

For the unattended-but-stop-on-blocker execution mode, use:

- [2026-03-30-core-matrix-phase-2-sequential-execution-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-30-core-matrix-phase-2-sequential-execution-design.md)
- [2026-03-30-core-matrix-phase-2-milestone-d-sequential-execution-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-core-matrix-phase-2-milestone-d-sequential-execution-plan.md)
- [2026-03-30-core-matrix-phase-2-milestone-e-sequential-execution-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-core-matrix-phase-2-milestone-e-sequential-execution-plan.md)
- [2026-03-30-core-matrix-phase-2-milestone-f-sequential-execution-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-core-matrix-phase-2-milestone-f-sequential-execution-plan.md)

These documents do not replace the detailed task docs below. They define the
execution order, milestone gates, stop rules, and acceptance packaging for the
remaining Phase 2 batch.

Completed milestone archives:

- `Milestone A`:
  [2026-03-26-core-matrix-phase-2-milestone-a-substrate-adjustments.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-26-core-matrix-phase-2-milestone-a-substrate-adjustments.md)
- `Milestone B`:
  [2026-03-26-core-matrix-phase-2-milestone-b-provider-execution-foundation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-26-core-matrix-phase-2-milestone-b-provider-execution-foundation.md)
- `Milestone C`:
  [2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md)

## Remaining Phase 2 Milestones

### Milestone D: Kernel Runtime Breadth

- `Task D1`: [2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md)
- `Task D2`: [2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md)

### Milestone E: Capability And Connector Breadth

- `Task E1`: [2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md)
- `Task E2`: [2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md)

### Milestone F: Validation Breadth And Acceptance

- `Task F1`: [2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md)
- `Task F2`: [2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md)
- `Task F3`: [2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md)

## Success Criteria

- mailbox-driven control works through `poll`, and through `WebSocket` when a
  realtime link is present
- Protocol E2E harness and golden scenarios for mailbox, interrupt, and close
  behavior are established in Milestone C and remain separate from later Web
  UI end-to-end coverage
- `turn_interrupt` is a tested kernel primitive and fences stale retry or
  stale completion correctly
- archive and delete reuse the close model without collapsing into the same
  lifecycle semantics
- a real provider-backed turn reaches terminal or waiting state under workflow
  control
- step-level retry works inside the current turn without forcing a full
  workflow restart
- at least one human-interaction wait path and one subagent path work in a
  real run
- governed capability use works for both agent-owned and MCP-backed paths
- bundled `Fenix`, independent external `Fenix`, and same-installation
  deployment rotation all validate in real runs
- workflow proof exports and proof markdown artifacts are captured as formal
  manual-validation evidence
- the phase passes automated tests plus real-environment validation under
  `bin/dev` with a real LLM API

## Core Matrix Work

- keep the kernel authoritative over workflow progression, close fences,
  retries, and terminal state
- keep the current root chain and runtime lineage authoritative instead of
  layering replacement ledgers for the same lifecycle facts
- make mailbox semantics canonical for control work
- keep `poll` as a complete fallback control path even when `WebSocket` is the
  preferred realtime delivery path
- split deployment presence from deployment health
- add durable close lifecycle fields to closable runtime resources
- add `ConversationCloseOperation` to track archive and delete orchestration
- preserve `message_retry`, `delivery_retry`, `step_retry`,
  `workflow_resume`, `workflow_retry`, and `close_escalation` as distinct
  protocol or recovery modes
- preserve execution-time budget hints and runtime-stage hooks without moving
  prompt building back into the kernel
- keep workflow yield, presentation policy, and proof-export work aligned with
  the new close and retry semantics

## Fenix Validation Scope

`agents/fenix` remains the default validation program for this phase.

It should prove:

- normal assistant, coding, and office-assistance conversations
- one interrupted turn
- one retryable step failure resumed inside the same turn
- one archive flow and one delete flow under mailbox-driven close control
- one independently paired external `Fenix` runtime
- one same-installation deployment rotation across release change
- one built-in system skill that deploys another agent
- one third-party Agent Skills package installed and used successfully

## Out Of Scope

- Web UI productization
- workspace-owned trigger infrastructure
- IM, PWA, or desktop channels
- extension and plugin packaging
- kernel-owned prompt building
- kernel-owned universal compaction or summarization
- a `Fenix` self-update daemon or plugin marketplace
