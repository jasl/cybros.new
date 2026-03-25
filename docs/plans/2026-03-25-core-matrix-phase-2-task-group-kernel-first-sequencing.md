# Core Matrix Phase 2 Task Group: Kernel-First Sequencing

## Status

Active sequencing note for the earliest `Core Matrix` tasks inside Phase 2.

## Purpose

Define the recommended early ordering for the kernel-owned work so Phase 2
lands the control model, close semantics, and workflow safety before broader
runtime breadth.

## Sequencing Principles

1. Land workflow substrate before mailbox control.
2. Land mailbox control before provider breadth.
3. Land turn interrupt and close semantics before archive, delete, and retry
   behavior are validated in product flows.
4. Land stale-work and feature-policy safety before broader multi-turn
   validation.
5. Treat `Fenix` as the consumer of a stable kernel contract, not as the place
   where that contract is discovered.

## Recommended Early Sequence

### Task 1: Workflow Substrate Extensions

Primary outcome:

- workflow-owned storage exists for yield markers, barrier summaries,
  presentation policy, and successor metadata
- later close, retry, and proof work has a stable substrate to target

Detailed execution unit:

- [2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md)

### Task 2: Mailbox Control And Resource Close Contract

Primary outcome:

- mailbox items exist as the durable control surface
- `AgentTaskRun` exists as the workflow-owned execution resource
- `poll`, `WebSocket`, and response piggyback share one control envelope
- close commands and close acknowledgements are durable and testable

Detailed execution unit:

- [2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md)

### Task 3: Turn Interrupt And Conversation Close Semantics

Primary outcome:

- `turn_interrupt` is a kernel primitive
- close fences prevent stale retry or stale completion from reviving stopped
  work
- archive and delete run through `ConversationCloseOperation` and the resource
  close protocol
- retryable step failure feeds `step_retry`, not `workflow_retry`

Detailed execution unit:

- [2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md)

### Task 4: Provider-Backed Turn Execution

Primary outcome:

- one real `turn_step` runs under mailbox delivery and workflow control
- provider execution routes through `simple_inference`
- authoritative provider usage is persisted for later advisory logic

Detailed execution unit:

- [2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md)

### Task 5: Conversation Policy And Stale-Work Safety

Primary outcome:

- conversation feature policy is authoritative
- `reject / restart / queue` semantics are real
- stale or superseded work cannot commit onto the wrong tail after newer input
  or selector movement
- this task does not redefine turn-interrupt fences or archive/delete close
  behavior

Detailed execution unit:

- [2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md)

### Task 6: Wait-State Handoff, Human Interaction, And Subagents

Primary outcome:

- human input and subagent coordination enter kernel-owned wait states rather
  than runtime-local pause modes
- the wait model established for `retryable_failure` is reused rather than
  redefined here
- resume and retry paths remain coherent with close fences

Detailed execution unit:

- [2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md)

### Task 7: Base Capability Governance

Primary outcome:

- governed capability bindings freeze correctly
- retries and recovery preserve or renew bindings intentionally

Detailed execution unit:

- [2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md)

### Task 8: Streamable HTTP MCP Under The Same Governance

Primary outcome:

- one real MCP path works under the same mailbox, retry, close, and
  governance rules already proven for the kernel base

Detailed execution unit:

- [2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md)
