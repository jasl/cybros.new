# Core Matrix Phase 2 Design: Conversation-First Subagent Threads

Use this design document before starting the Phase 2 restructuring batch that
replaces workflow-owned `SubagentRun` rows with conversation-first subagent
threads.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
4. `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
5. `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
6. `docs/plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md`

## Purpose

Phase 2 currently models subagents as workflow-owned runtime rows:

- `SubagentRun` owns the durable coordination record
- `ExecutionLease` owns runtime heartbeat ownership
- `subagent_spawn` is exposed as an ordinary tool-catalog entry

That shape is materially worse than the approved target:

- subagents do not have their own conversation transcript
- subagent lifecycle is anchored to workflow nodes instead of conversation
  ownership
- close, archive, delete, and purge semantics have to special-case
  workflow-owned residue
- the capability surface cannot cleanly express reserved platform-level
  controls such as `subagent_wait`, `subagent_send`, or `subagent_close`

This design replaces that model with a conversation-first architecture:

- every subagent owns a child `Conversation`
- a new `SubagentThread` row is the durable control aggregate
- `AgentTaskRun(kind = "subagent_step")` remains the reusable execution
  instance
- existing mailbox, close-control, close-reconciliation, and conversation
  lineage infrastructure stay in place

This batch is intentionally breaking:

- no compatibility shims
- no dual-track `SubagentRun` and `SubagentThread` model
- no data backfill
- no legacy docs kept alive for transition wording

## Design Constraints

- `references/` informed the discussion, but the landed design is defined only
  by `core_matrix` contracts, tests, and behavior docs.
- External and agent-facing boundaries continue to use `public_id`; no raw
  `bigint` identifiers may leak.
- Fork, branch, thread, and checkpoint creation remain conversation-lineage
  operations only. They do not inherit, share, or reveal parent subagent
  threads in this batch.
- Human callers may not directly address subagent conversations in this batch.
- The implementation must reuse existing close-control and capability-composer
  infrastructure instead of inventing parallel protocol stacks.

## Four Scan Passes

The repository was scanned in four focused passes before writing this design.
No new architectural areas appeared after the fourth pass.

### Pass 1: Existing Subagent Surface

Scanned:

- `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- `core_matrix/app/models/subagent_run.rb`
- `core_matrix/app/services/subagents/spawn.rb`
- `core_matrix/app/models/agent_task_run.rb`
- `core_matrix/test/services/subagents/spawn_test.rb`

Findings:

- current subagent coordination is workflow-owned, not conversation-owned
- `SubagentRun` carries speculative fields (`depth`, `batch_key`,
  `coordination_key`) that do not belong in the approved conversation-first
  model
- `AgentTaskRun(kind = "subagent_step")` already exists and should be reused

### Pass 2: Control Plane, Capability Surface, And Close Routing

Scanned:

- `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- `core_matrix/app/models/runtime_capability_contract.rb`
- `core_matrix/app/services/agent_control/closable_resource_registry.rb`
- `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- `core_matrix/test/requests/agent_api/capabilities_test.rb`
- `core_matrix/test/services/agent_deployments/handshake_test.rb`

Findings:

- `CORE_MATRIX_TOOL_CATALOG` is already the correct insertion point for
  reserved platform tools
- close control already has one reusable mailbox protocol and one
  `ClosableRuntimeResource` concern
- `SubagentRun` is wired into close registry and close outcome handling and
  must be cleanly replaced there

### Pass 3: Conversation Lifecycle, Purge, And Lineage

Scanned:

- `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- `core_matrix/app/services/conversations/archive.rb`
- `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- `core_matrix/app/services/conversations/purge_plan.rb`
- `core_matrix/app/services/conversations/finalize_deletion.rb`
- `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- `core_matrix/test/services/conversations/archive_test.rb`
- `core_matrix/test/services/conversations/purge_deleted_test.rb`

Findings:

- subagent lifecycle must plug into the existing owner-conversation close,
  archive, delete, and purge model rather than creating a second resource
  ownership graph
- purge currently explicitly tears down `SubagentRun`; the purge graph must be
  rewritten around owned subagent conversations and `SubagentThread`
- blocker queries already expose the right extension seam for replacing running
  subagent counts

### Pass 4: Audit Surface, Events, Schema, And Exhaustiveness

Scanned:

- `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- `core_matrix/app/models/conversation.rb`
- `core_matrix/app/models/message.rb`
- `core_matrix/app/models/workflow_artifact.rb`
- `core_matrix/db/migrate/20260324090038_create_subagent_runs.rb`
- `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
- exhaustive `rg` across `core_matrix/app`, `core_matrix/test`,
  `core_matrix/docs`, and `core_matrix/db`

Findings:

- `ConversationEvent` is the right existing projection surface for operational
  subagent notifications and sender audit; no second audit log should be added
- `Conversation` currently lacks an addressability axis and needs one
- migration history can be rewritten directly because the database will be
  rebuilt for this batch
- no additional hidden `SubagentRun` ownership surfaces appeared after the
  exhaustive grep

## Test Scenario Matrix

These scenarios must exist in tests before the batch is considered complete.
Keep them visible at the top of the implementation plan and land them in this
approximate order.

### Model And Schema Scenarios

1. `Conversation` supports `addressability = owner_addressable | agent_addressable`.
2. `SubagentThread` requires one owner conversation and one child conversation.
3. `SubagentThread` rejects owner or child conversations from a different
   installation.
4. `SubagentThread` rejects `scope = turn` without `origin_turn_id`.
5. `SubagentThread` uses `ClosableRuntimeResource` and enforces close metadata
   pairings without inventing a second close-state machine.
6. `AgentTaskRun(kind = "subagent_step")` may reference one `subagent_thread`
   and one `requested_by_turn` in addition to its child conversation turn.
7. `ExecutionLease` accepts `SubagentThread` instead of `SubagentRun` in the
   leased-resource allowlist.

### Capability And Protocol Scenarios

8. capabilities always expose reserved Core Matrix tools
   (`subagent_spawn`, `subagent_send`, `subagent_wait`, `subagent_close`,
   `subagent_list`) through `effective_tool_catalog`
9. environment and agent snapshots cannot shadow or redefine those reserved
   tool names
10. registration and handshake flows still return a stable combined capability
    contract after the reserved tools are injected

### Spawn And Message Flow Scenarios

11. `subagent_spawn(scope: "turn")` creates:
    - one child conversation with `kind = "thread"`
    - `purpose = "interactive"`
    - `addressability = "agent_addressable"`
    - one `SubagentThread`
    - one initial child turn/workflow/task dispatch
12. `subagent_spawn(scope: "conversation")` creates the same structure but
    remains reusable across later owner turns.
13. standard human turn-entry APIs reject writes to an
    `agent_addressable` conversation.
14. `subagent_send` rejects senders other than:
    - the owner conversation agent
    - the subagent itself
    - the system
15. every accepted agent-authored subagent message produces one
    `ConversationEvent` audit projection on the child conversation.
16. `subagent_list` returns only threads owned by the current conversation and
    only by `public_id`.

### Wait, Close, And Notification Scenarios

17. `subagent_wait` returns immediately for a terminal durable state and
    returns a timeout result without mutating state otherwise.
18. `subagent_close` is idempotent for an already closed thread.
19. a close request for a running subagent thread routes through the existing
    mailbox close-control protocol and updates `SubagentThread.close_state`.
20. terminal close reports re-enter
    `Conversations::ReconcileCloseOperation` through the owner conversation.
21. owner-conversation event projection records `subagent_thread.opened`,
    terminal completion or failure, and close outcomes through
    `ConversationEvent` rather than transcript messages.

### Turn Interrupt, Archive, Delete, And Purge Scenarios

22. turn interrupt closes turn-scoped subagent threads created by that turn.
23. turn interrupt interrupts in-flight `subagent_step` work requested by the
    interrupted owner turn even when the thread itself is
    `scope = "conversation"`.
24. turn interrupt leaves a conversation-scoped thread reusable after its
    in-flight work has been interrupted.
25. archive without force rejects while any owned subagent thread remains open.
26. archive force blocks new `spawn` and `send` requests immediately and
    issues close requests for owned open subagent threads.
27. delete and purge fail closed if an owner conversation still has open or
    close-pending subagent threads.
28. purge deletes owned child subagent conversations, their task runs, mailbox
    rows, report receipts, and event projections without leaking residue.

### Lineage And Cleanup Scenarios

29. branch, thread, checkpoint, and fork creation do not inherit or expose
    parent `SubagentThread` rows or subagent conversations.
30. no remaining code, tests, docs, migrations, or schema references mention
    `SubagentRun`.

## Impacted Files And Cleanup Map

This is the minimum file set the implementation plan must cover. Delete or
rewrite obsolete surfaces; do not leave stale terminology behind.

### Schema And Models

- Create: `core_matrix/app/models/subagent_thread.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/models/execution_lease.rb`
- Modify: `core_matrix/app/models/workflow_artifact.rb`
- Delete: `core_matrix/app/models/subagent_run.rb`
- Rewrite: `core_matrix/db/migrate/20260324090038_create_subagent_runs.rb`
- Rewrite: `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
- Regenerate: `core_matrix/db/schema.rb`

### Services And Queries

- Create: `core_matrix/app/services/subagent_threads/spawn.rb`
- Create: `core_matrix/app/services/subagent_threads/send_message.rb`
- Create: `core_matrix/app/services/subagent_threads/list_for_conversation.rb`
- Create: `core_matrix/app/services/subagent_threads/wait.rb`
- Create: `core_matrix/app/services/subagent_threads/request_close.rb`
- Create: `core_matrix/app/services/subagent_threads/validate_addressability.rb`
- Create: `core_matrix/app/services/turns/start_agent_turn.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/services/agent_control/closable_resource_registry.rb`
- Modify: `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- Modify: `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Modify: `core_matrix/app/services/agent_control/report.rb`
- Modify: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Modify: `core_matrix/app/services/conversations/request_resource_closes.rb`
- Modify: `core_matrix/app/services/conversations/progress_close_requests.rb`
- Modify: `core_matrix/app/services/conversations/archive.rb`
- Modify: `core_matrix/app/services/conversations/create_thread.rb`
- Modify: `core_matrix/app/services/conversations/finalize_deletion.rb`
- Modify: `core_matrix/app/services/conversations/purge_plan.rb`
- Modify: `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Delete: `core_matrix/app/services/subagents/spawn.rb`

### Tests

- Create: `core_matrix/test/models/subagent_thread_test.rb`
- Create: `core_matrix/test/services/subagent_threads/spawn_test.rb`
- Create: `core_matrix/test/services/subagent_threads/send_message_test.rb`
- Create: `core_matrix/test/services/subagent_threads/wait_test.rb`
- Create: `core_matrix/test/services/subagent_threads/request_close_test.rb`
- Create: `core_matrix/test/services/turns/start_agent_turn_test.rb`
- Modify: `core_matrix/test/models/agent_task_run_test.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/models/execution_lease_test.rb`
- Delete: `core_matrix/test/models/subagent_run_test.rb`
- Delete: `core_matrix/test/services/subagents/spawn_test.rb`
- Modify: `core_matrix/test/services/conversations/archive_test.rb`
- Modify: `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- Modify: `core_matrix/test/services/conversations/purge_deleted_test.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
- Modify: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Modify: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Modify: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Modify: `core_matrix/test/requests/agent_api/capabilities_test.rb`
- Modify: `core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

### Behavior Docs

- Rewrite: `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`

## Approved Design

### 1. Core Architecture

Subagents become conversation-scoped collaboration threads, not workflow-owned
runtime rows.

Each subagent consists of two durable records:

1. one child `Conversation`
2. one `SubagentThread` control row that points at that child conversation and
   its owner conversation

The child conversation reuses existing conversation infrastructure:

- conversation lineage
- transcript storage
- turn/workflow/task orchestration
- canonical store reference
- runtime binding to the same execution environment as the owner conversation

The new `SubagentThread` row exists only to hold control-plane facts that do
not belong on `Conversation` itself:

- owner conversation
- origin turn
- scope
- requested role or slot
- durable open or closed availability
- close-control state
- last known execution status

This keeps transcript history and control lifecycle orthogonal instead of
putting both concerns on one model.

### 2. Conversation Rules

The child subagent conversation uses existing conversation axes wherever
possible:

- `kind = "thread"`
- `purpose = "interactive"`
- `execution_environment` is inherited from the owner conversation

One new axis is added to `Conversation`:

- `addressability = "owner_addressable" | "agent_addressable"`

Rules:

- top-level user and automation conversations remain `owner_addressable`
- all subagent conversations are `agent_addressable`
- standard human turn-entry and live mutation paths reject direct writes to an
  `agent_addressable` conversation
- fork, branch, thread, and checkpoint creation remain unchanged except that
  they do not inherit, share, or reveal parent subagent threads

No new conversation kind is introduced. `kind` continues to describe lineage
shape only.

### 3. `SubagentThread` Contract

`SubagentThread` is the durable control aggregate. Its fields should be kept
minimal and should reuse existing close-control conventions:

- `public_id`
- `installation_id`
- `owner_conversation_id`
- `conversation_id`
- `origin_turn_id`
- `scope = "turn" | "conversation"`
- `requested_role_or_slot`
- optional `nickname`
- `lifecycle_state = "open" | "closed"`
- `last_known_status = "idle" | "running" | "waiting" | "completed" | "failed" | "interrupted"`
- `closed_at`
- `close_reason_kind`
- the standard `ClosableRuntimeResource` fields:
  - `close_state`
  - `close_requested_at`
  - `close_grace_deadline_at`
  - `close_force_deadline_at`
  - `close_acknowledged_at`
  - `close_outcome_kind`
  - `close_outcome_payload`

Deliberately not carried forward from `SubagentRun`:

- `depth`
- `batch_key`
- `coordination_key`
- `parent_subagent_run_id`
- `terminal_summary_artifact_id`
- any `agent_path` tree

Those fields were tied to workflow fan-out semantics. They are not required by
the approved conversation-first model.

### 4. Execution Model

`SubagentThread` does not replace `AgentTaskRun`. It reuses it.

Each accepted `subagent_spawn` or `subagent_send` request allocates work in the
child conversation using the existing turn and workflow machinery:

- append the agent-authored input to the child conversation
- create or reuse the child thread conversation through
  `Conversations::CreateThread`
- allocate child execution through a dedicated `Turns::StartAgentTurn`
  service plus the existing workflow builders
- create `AgentTaskRun(kind = "subagent_step")`

For `subagent_step`, `AgentTaskRun` must carry both:

- `turn_id`: the child conversation turn being executed
- `requested_by_turn_id`: the owner conversation turn that requested this
  dispatch
- `subagent_thread_id`: the thread whose child work is being executed

This distinction is required for turn interrupt correctness:

- a turn interrupt must close turn-scoped threads created by the interrupted
  owner turn
- the same interrupt must also stop in-flight child work requested by that
  owner turn even if the thread itself is conversation-scoped
- the conversation-scoped thread remains reusable after that child work is
  interrupted

### 5. Reserved Platform Tool Surface

Subagent control becomes a platform-owned capability, not an environment or
agent-program capability.

Reserved tool names:

- `subagent_spawn`
- `subagent_send`
- `subagent_wait`
- `subagent_close`
- `subagent_list`

Rules:

- these tool definitions are injected through
  `RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG`
- agent and environment tool snapshots may not redefine or override those
  names
- registration and handshake still record the agent's own tool catalog, but
  the effective catalog always includes the reserved Core Matrix entries
- this batch does not add nested subagent spawning from inside subagent
  conversations; reserved tools are exposed only on owner conversations that
  remain `owner_addressable`

### 6. Message Entry And Audit

All writes to an `agent_addressable` conversation must pass through dedicated
services. There is no UI-only or controller-only guard.

Allowed sender kinds in this batch:

- `owner_agent`
- `subagent_self`
- `system`

Rejected sender kinds in this batch:

- `human`
- `foreign_agent`
- `sibling_subagent`

The implementation should stay lightweight:

- do not add sender columns to `messages`
- append transcript-bearing `Message` rows through the normal conversation and
  turn infrastructure
- project sender audit and lifecycle notifications through `ConversationEvent`

Required event families:

- `subagent_thread.opened`
- `subagent_thread.message_delivered`
- `subagent_thread.completed`
- `subagent_thread.failed`
- `subagent_thread.closed`

Each event must record enough payload to audit:

- `subagent_thread_public_id`
- `sender_kind`
- `sender_conversation_public_id` when applicable
- `causation_message_public_id` or task `public_id` when applicable

### 7. Close, Wait, Archive, Delete, And Purge

`SubagentThread` must plug into existing close-control infrastructure rather
than inventing a second lifecycle protocol.

Reuse:

- `ClosableRuntimeResource`
- `AgentControl::CreateResourceCloseRequest`
- `AgentControlMailboxItem`
- `AgentControl::ApplyCloseOutcome`
- `Conversations::ReconcileCloseOperation`

Behavior:

- `subagent_wait` reads durable state first and only waits while the thread is
  still open and non-terminal
- `subagent_close` is idempotent and targets the child runtime through the
  existing close mailbox contract
- archive without force rejects while any owned thread remains open
- archive force blocks new `spawn` and `send` requests and requests close for
  owned open threads
- delete and purge refuse to finalize while owned subagent threads remain open
  or close-pending
- purge removes:
  - owned `SubagentThread` rows
  - owned child subagent conversations
  - owned child turns and messages
  - owned child `AgentTaskRun` rows
  - owned mailbox items and report receipts
  - owned `ConversationEvent` rows

### 8. Fork And Lineage

This batch explicitly adopts the same high-level rule as other owned runtime
residue:

- fork, branch, thread, and checkpoint creation do not inherit live subagent
  threads
- descendant conversations do not even see parent-owned subagent threads
- the child conversation created for a subagent thread belongs only to the
  owner conversation and its purge graph

This is intentional. It prevents branch pollution, shared live workers, and
ambiguous close ownership.

### 9. Orthogonality And Reuse Check

The new design is acceptable only if it stays orthogonal to the rest of Core
Matrix and reuses existing infrastructure.

Required reuse points:

- `Conversation` remains the single transcript, lineage, and canonical-store
  aggregate
- `AgentTaskRun` remains the single execution-instance aggregate
- `ConversationEvent` remains the single non-transcript operational projection
  surface
- `ConversationCloseOperation` remains the single owner-conversation close
  orchestration state machine
- `AgentControlMailboxItem` and `AgentControlReportReceipt` remain the single
  durable control-plane transport
- `ClosableRuntimeResource` remains the single close metadata contract

Required non-goals:

- no second subagent-only mailbox protocol
- no second subagent-only event store
- no `SubagentRun` compatibility shell
- no special lineage rules just for subagent conversations
- no speculative nested-agent tree metadata

### 10. Acceptance Criteria

The batch is complete only when all of the following are true:

1. `SubagentRun` no longer exists in `core_matrix/app`, `core_matrix/test`,
   `core_matrix/docs`, `core_matrix/db`, or `core_matrix/db/schema.rb`.
2. All subagent conversations are ordinary `Conversation` rows with
   `addressability = "agent_addressable"`.
3. All subagent control state is carried by `SubagentThread`.
4. All child execution work reuses `AgentTaskRun(kind = "subagent_step")`.
5. All owner-conversation close, archive, delete, and purge flows work
   without leaking subagent residue.
6. Reserved subagent tool names are injected by Core Matrix and cannot be
   overridden by runtime snapshots.
7. Human callers cannot directly write to subagent conversations.
8. The behavior docs, tests, schema, and code all use the same terminology.

## Blockers

No unresolved blockers remain at the design level.

Two scope boundaries are intentional and must not be reopened during
implementation:

- nested subagent spawning is out of scope for this batch
- fork inheritance of subagent threads is out of scope for this batch

If implementation work discovers a requirement that violates either boundary,
stop and reopen design discussion instead of ad hoc extending the model.
