# Core Matrix Phase 2 Milestone: Agent Loop Execution

## Status

Active milestone definition for the current post-substrate execution phase.

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

## Related Design And Research

- [2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md)
- [2026-03-25-core-matrix-platform-phases-and-validation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md)
- [2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md)
- [2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md)
- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)
- [2026-03-25-fenix-phase-2-validation-and-skills-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md)

## Formal Execution Units

Activate and execute Phase 2 through these focused task documents:

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

## Success Criteria

- mailbox-driven control works through `poll`, and through `WebSocket` when a
  realtime link is present
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
