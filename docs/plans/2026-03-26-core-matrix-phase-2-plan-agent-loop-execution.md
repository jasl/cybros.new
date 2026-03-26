# Core Matrix Phase 2 Plan: Agent Loop Execution

## Status

Active phase-level plan for the current post-substrate execution phase.

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
- [2026-03-26-core-matrix-phase-2-execution-environment-and-agent-runtime-boundary-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-execution-environment-and-agent-runtime-boundary-design.md)
- [2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)
- [2026-03-25-fenix-phase-2-validation-and-skills-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md)

## Current Implementation Milestones

The current implementation focus should complete Milestones A through C,
including the `Task C5` runtime-boundary follow-up, before the later breadth
and validation milestones.

## Active Execution Order

The active unattended execution batch for the current phase is:

1. `Task A1`
2. `Task A2`
3. `Task B1`
4. `Task C1`
5. `Task C2`
6. `Task C3`
7. `Task C4`
8. `Task C5`
9. `Task C2 Follow-Up`

Later milestones remain explicitly out of the current execution batch until the
Milestone C follow-up task set is complete and re-verified.

### Milestone A: Substrate Adjustments

- [2026-03-26-core-matrix-phase-2-milestone-a-substrate-adjustments.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-milestone-a-substrate-adjustments.md)
- `Task A1`: [2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md)
- `Task A2`: [2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md)

### Milestone B: Provider Execution Foundation

- [2026-03-26-core-matrix-phase-2-milestone-b-provider-execution-foundation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-milestone-b-provider-execution-foundation.md)
- `Task B1`: [2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md)

### Milestone C: Runtime Pairing And Control

- [2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md)
- `Task C1`: [2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md)
- `Task C2`: [2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md)
- `Task C3`: [2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md)
- `Task C4`: [2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md)
- `Task C5`: [2026-03-26-core-matrix-phase-2-task-execution-environment-runtime-boundary-follow-up.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-execution-environment-runtime-boundary-follow-up.md)
- `Task C2 Follow-Up`: [2026-03-27-core-matrix-phase-2-plan-close-operation-reconciliation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-close-operation-reconciliation.md)
- `Task C6 Follow-Up`: [2026-03-27-core-matrix-phase-2-plan-runtime-binding-and-rewrite-safety-hardening.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-runtime-binding-and-rewrite-safety-hardening.md)
- `Task C7 Follow-Up`: [2026-03-27-core-matrix-phase-2-plan-conversation-mutation-contract-unification.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-conversation-mutation-contract-unification.md)
- `Task C8 Follow-Up`: [2026-03-27-core-matrix-phase-2-plan-lineage-provenance-and-supersession-hardening.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-lineage-provenance-and-supersession-hardening.md)
- `Task C9 Follow-Up`: [2026-03-27-core-matrix-phase-2-plan-anchor-lineage-and-provenance-regression-hardening.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-anchor-lineage-and-provenance-regression-hardening.md)
- `Task C10 Follow-Up`: [2026-03-26-core-matrix-phase-2-plan-conversation-purge-hardening.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-plan-conversation-purge-hardening.md)
- `Task C11 Follow-Up`: [2026-03-26-core-matrix-phase-2-plan-review-audit.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-plan-review-audit.md)

## Later Phase 2 Milestones

Later Phase 2 breadth should continue only after Milestone C plus its active
runtime-boundary and hardening follow-ups are stable.

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
