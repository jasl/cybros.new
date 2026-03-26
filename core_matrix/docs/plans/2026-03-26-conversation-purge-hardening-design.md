# Conversation Purge Hardening Design

## Goal

Harden `Conversations::PurgeDeleted` so that physical purge:

- removes all conversation-owned runtime residue, including phase-two
  agent-control rows
- minimizes post-purge data damage by preserving model teardown where Rails or
  Active Storage semantics matter
- fails closed when any owned rows still remain
- keeps delete / finalize / purge behavior aligned with the documented
  conversation lifecycle

## Problem Summary

The current purge path is an explicit manual delete chain. That is consistent
with the product's deletion contract, but it is now incomplete.

- phase-two agent-control state introduced `agent_task_runs`,
  `agent_control_mailbox_items`, and `agent_control_report_receipts`
- `Conversations::PurgeDeleted` still deletes around `workflow_runs` rather than
  through a centralized ownership graph
- some purge-owned objects carry teardown semantics that should not be skipped,
  especially `MessageAttachment` and `WorkflowArtifact`, both of which use
  `has_one_attached :file`
- `AgentControlMailboxItem` and `AgentControlReportReceipt` can be only
  partially connected to `AgentTaskRun`, so cleanup cannot rely on a single
  direct foreign-key chain

The result is a maintenance-heavy purge path that can now miss rows and leave
residue behind even when the conversation shell is otherwise ready to disappear.

## Current Constraints

- delete remains a staged lifecycle:
  `retained -> pending_delete -> deleted -> physically purged`
- `Conversations::FinalizeDeletion` still owns removal of the live
  `CanonicalStoreReference`
- `Conversations::PurgeDeleted(force: true)` may request close/quiescence work,
  but it does not bypass final deletion, lineage guards, or provenance guards
- this codebase intentionally uses `dependent: :restrict_with_exception` on the
  majority of conversation-runtime associations, so purge is not supposed to be
  delegated to broad Active Record cascades
- external or agent-facing boundaries still use `public_id`, not internal ids

## Decision Summary

Keep purge as an explicit service-owned protocol, but refactor it into a
centralized purge graph with mixed deletion semantics.

### Why this approach

- it preserves the current product model, where deletion is a protocol-driven
  lifecycle rather than a normal `destroy` tree
- it makes new runtime tables visible during future schema work because every
  owned row class must be assigned to a purge stage
- it avoids overloading model associations with `dependent: :destroy` behavior
  that would blur the boundary between lifecycle orchestration and physical
  cleanup
- it allows selective use of `destroy!` only where Rails teardown semantics are
  needed

### Rejected alternatives

#### 1. Keep the current delete chain and just append the missing tables

Rejected because it solves today's omission without changing the structure that
caused it. Future runtime tables would be easy to miss again.

#### 2. Push purge into model-level `dependent: :destroy` or `dependent: :delete_all`

Rejected because the product already treats delete/finalize/purge as explicit
conversation lifecycle phases. A broad AR cascade would make physical cleanup
too implicit and harder to audit.

#### 3. Convert the whole purge to `model.delete` or `destroy!`

Rejected because neither extreme is right:

- broad `delete` still skips teardown and does not reduce damage by itself
- broad `destroy!` would load too much object graph and would make self-
  referential runtime trees harder to clean predictably

## Proposed Architecture

Introduce a dedicated purge graph object, referenced here as
`Conversations::PurgePlan`.

`Conversations::PurgeDeleted` becomes a thin orchestrator that:

1. validates lifecycle and blocker preconditions
2. optionally triggers force quiescence
3. builds the purge plan under lock
4. executes the plan stage-by-stage inside the transaction
5. verifies no owned rows remain
6. removes the final conversation shell

`Conversations::PurgePlan` owns:

- id collection for conversation-owned runtime rows
- owner resolution for rows that are not directly keyed by conversation
- stage ordering
- deletion semantics per stage
- post-plan verification scopes

## Ownership Model

The purge graph uses owner resolution rather than assuming that every row has a
direct `conversation_id`.

### Directly owned rows

These can be collected directly from the conversation or its workflow runs:

- `workflow_runs`
- `turns`
- `messages`
- `publications`
- `conversation_close_operations`
- `conversation_message_visibilities`
- `conversation_events`
- `human_interaction_requests`
- `conversation_imports`
- `conversation_summary_segments`
- `message_attachments`

### Workflow-owned runtime rows

These are owned through the conversation's workflow runs or turns:

- `workflow_nodes`
- `workflow_edges`
- `workflow_node_events`
- `workflow_artifacts`
- `process_runs`
- `subagent_runs`
- `agent_task_runs`
- `execution_leases`

### Mailbox-owned residue

These rows need explicit owner-resolution logic because they are not always
reachable through `agent_task_run_id`.

- execution-assignment mailbox items are owned through `agent_task_run_id`
- resource-close mailbox items for `ProcessRun` and `SubagentRun` can exist with
  `agent_task_run_id = nil`, so ownership must also be resolved from
  `payload["resource_type"]` and `payload["resource_id"]`
- report receipts must be removed by either `mailbox_item_id` or
  `agent_task_run_id`, because either link can be absent depending on the
  report kind

This means the plan must treat mailbox items as a first-class purge-owned set,
not as a derivative of `agent_task_runs` only.

## Deletion Semantics

The purge graph uses three deletion modes.

### Mode 1: Bulk `delete_all` for pure runtime rows

Use bulk delete for rows whose cleanup semantics are purely relational and do
not depend on callbacks or attachment teardown.

This includes:

- `PublicationAccessEvent`
- `Publication`
- `ConversationCloseOperation`
- `ConversationMessageVisibility`
- `ConversationEvent`
- `HumanInteractionRequest`
- `AgentControlReportReceipt`
- `AgentControlMailboxItem`
- `ExecutionLease`
- `AgentTaskRun`
- `ProcessRun`
- `SubagentRun`
- `WorkflowNodeEvent`
- `WorkflowEdge`
- `WorkflowNode`
- `WorkflowRun`
- `ConversationImport`
- `ConversationSummarySegment`
- `Message`
- `Turn`
- `CanonicalStoreReference`
- `ConversationClosure`

### Mode 2: teardown-aware `destroy!` for attachment-backed rows

Use model destruction for rows that carry Active Storage teardown semantics.

This includes:

- `MessageAttachment`
- `WorkflowArtifact`

These rows should be destroyed before their parent `Message` /
`WorkflowNode` / `WorkflowRun` records are bulk-deleted so attachment cleanup
can run while the owning records still exist. The expected teardown result is
that both the model rows and their `active_storage_attachments` join rows
disappear.

### Mode 3: final shell `delete`

Use `delete` for the final conversation row once every owned row has been
removed and verification has passed.

The reason is not that `delete` is intrinsically safer. The reason is that the
conversation shell should already be an empty tombstone at that point, and
physical purge should not depend on future model callbacks.

## Purge Graph Order

The purge graph executes in this order:

1. collect ids for conversation, workflow, runtime, mailbox, and attachment
   scopes under lock
2. delete publication rows:
   `publication_access_events -> publications`
3. delete mailbox residue:
   `agent_control_report_receipts -> agent_control_mailbox_items`
4. delete runtime leases:
   `execution_leases`
5. delete task and runtime rows:
   `agent_task_runs -> process_runs -> subagent_runs ->
   workflow_node_events -> workflow_edges`
6. destroy attachment-backed rows:
   `workflow_artifacts` and `message_attachments`
7. delete remaining workflow shell:
   `workflow_nodes -> workflow_runs`
8. delete conversation-owned metadata:
   `conversation_close_operations -> conversation_message_visibilities ->
   conversation_events -> human_interaction_requests ->
   conversation_imports -> conversation_summary_segments`
9. prepare transcript cleanup by nulling
   `turn.selected_input_message_id` / `selected_output_message_id`
10. destroy / remove transcript rows:
    `message_attachments already gone -> messages -> turns`
11. delete the conversation-side structural shell:
    `canonical_store_reference -> conversation_closures`
12. verify no owned rows remain
13. `delete` the conversation row

## Self-Reference and Edge Cases

The design must account for the following edge cases explicitly.

### Attachment ancestry

`MessageAttachment` has a self-reference through `origin_attachment_id`.

Before destroying in-scope message attachments, the purge plan should null
`origin_attachment_id` for rows inside the purge set. That avoids intra-set
destroy ordering problems and keeps teardown simple.

### Subagent self-reference

`SubagentRun` has a self-reference through `parent_subagent_run_id`, but those
rows remain in the bulk-delete group. A single bulk delete across the owned
subagent set is acceptable and avoids per-row ordering problems.

### Terminal artifact references

`SubagentRun` can point to `WorkflowArtifact` through
`terminal_summary_artifact_id`. The plan therefore deletes subagent runs before
destroying workflow artifacts.

### Execution leases

`ExecutionLease` is still deleted through `workflow_run_id`, which already
covers leases for `AgentTaskRun`, `ProcessRun`, and `SubagentRun`. The design
should document that explicitly so future work does not incorrectly duplicate
lease cleanup.

## Fail-Closed Verification

After executing all purge stages, the code must perform an explicit
`remaining_owned_rows?` verification.

If any owned scope still has rows, the conversation shell must not be deleted.

This verification should cover at least:

- workflow and transcript shells
- mailbox rows and receipts
- attachment-backed rows
- `active_storage_attachments` for purged `MessageAttachment` and
  `WorkflowArtifact` ids
- conversation metadata rows
- structural rows such as closures and canonical-store references

The design intent is fail-closed behavior:

- missing a purge stage leaves a tombstone shell behind
- missing a purge stage must not silently convert into physical deletion of the
  conversation row

## Testing Strategy

Add focused regression tests in
`test/services/conversations/purge_deleted_test.rb`.

### Test 1: phase-two agent-control residue

Create a deleted conversation that owns:

- an `AgentTaskRun`
- at least one execution-assignment mailbox item
- at least one resource-close mailbox item with `agent_task_run_id = nil`
- report receipts attached through both mailbox-item and task-run paths

Verify purge removes the conversation shell and all related mailbox/task rows.

### Test 2: attachment-backed teardown

Create a deleted conversation that owns:

- `MessageAttachment.file`
- `WorkflowArtifact.file`

Verify purge removes the owning rows and their corresponding
`active_storage_attachments`.

### Test 3: fail-closed shell behavior

Exercise a scenario where the purge graph would leave an owned row behind and
verify the conversation shell is not deleted.

The implementation may realize this through plan-level verification helpers or a
test-only seam, but the user-visible contract must be: residue blocks shell
removal.

## Documentation Updates Required During Implementation

The implementation must update these behavior docs to reflect the hardened
purge contract:

- `docs/behavior/conversation-structure-and-lineage.md`
- `docs/behavior/workflow-scheduler-and-wait-states.md`

The updated behavior documentation should state:

- purge now runs through an explicit ownership graph
- mailbox residue and attachment-backed runtime artifacts are part of physical
  cleanup
- shell removal is fail-closed when any owned rows remain
- `force: true` still requests normal close/quiescence work rather than bypassing
  lifecycle guards

## Acceptance Criteria

The hardening work is only complete when all of the following are true:

- `Conversations::PurgeDeleted` no longer misses phase-two agent-control rows
- resource-close mailbox items with `agent_task_run_id = nil` are still cleaned
  when they belong to the purged conversation's runtime resources
- attachment-backed rows are destroyed through teardown-aware code paths
- the conversation shell is removed only after an explicit no-residue
  verification passes
- focused purge regression tests cover agent-control residue, attachment
  teardown, and fail-closed shell behavior
- behavior docs describe the new purge contract precisely

## Task Relationship Model

The implementation work should remain sequential:

1. lock the missing behaviors with tests
2. introduce the purge graph abstraction
3. move `PurgeDeleted` onto the purge graph
4. add fail-closed verification and teardown-aware attachment cleanup
5. update behavior docs to match the shipped semantics
6. run focused and broader verification

This ordering is important because the tests define the intended contract before
the service structure changes.

## Automation Readiness

This work is suitable for fully automated execution because:

- the target files are explicit
- the desired behavior is stated as concrete testable outcomes
- the deletion order and teardown rules are defined up front
- documentation updates are scoped to named behavior artifacts
- completion is gated by regression tests and written docs, not by manual
  interpretation

## Documentation Integrity Check

The design was checked for completeness on `2026-03-26`.

- the task goal is explicit
- the root problem and rejected alternatives are explicit
- the ownership model distinguishes direct, workflow-owned, and mailbox-owned
  rows
- the mixed deletion strategy is defined rather than implied
- the edge cases include attachment ancestry, mailbox ownership, and terminal
  artifact references
- the acceptance criteria and execution order are explicit
- the document is sufficient to drive an automated implementation plan without
  inventing additional behavior rules
