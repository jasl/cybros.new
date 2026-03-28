# Core Matrix Phase 2 Design: Profile-Aware Conversation-First Subagent Sessions

Use this design document before starting the Phase 2 restructuring batch that
replaces workflow-owned `SubagentRun` rows with profile-aware,
conversation-first `SubagentSession` control.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
4. `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
5. `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
6. `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
7. `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
8. `docs/plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md`
9. `docs/plans/2026-03-28-core-matrix-phase-2-plan-conversation-first-subagent-sessions.md`

## Purpose

Phase 2 currently models subagents as workflow-owned runtime rows and exposes
`subagent_spawn` as an ordinary runtime tool. That shape is materially worse
than the approved target:

- subagents do not have their own conversation transcript
- subagent lifecycle is anchored to workflow nodes instead of conversation
  ownership
- capability contracts cannot express runtime-declared profiles or
  nested-subagent policy cleanly
- mailbox assignments do not carry the frozen runtime context that Fenix needs
- close, archive, delete, and purge semantics have to special-case
  workflow-owned residue

This batch replaces that model with a conversation-first architecture:

- every subagent owns a child `Conversation`
- a new `SubagentSession` row is the durable control aggregate
- `AgentTaskRun(kind = "subagent_step")` remains the reusable execution
  instance
- subagent behavior is driven by runtime-declared `profile` metadata, not by
  Core Matrix-owned prompt templates
- existing capability contracts, config snapshots, conversation override
  infrastructure, execution snapshots, mailbox control, and close
  reconciliation infrastructure stay in place

This batch is intentionally breaking:

- no compatibility shims
- no dual-track `SubagentRun` and `SubagentSession` model
- no data backfill
- no legacy docs kept alive for transition wording

## Naming Convergence

This revision intentionally converges terminology instead of preserving
history-driven naming drift.

- `Conversation` means transcript and lineage container only
- `Conversation.kind = "thread"` remains lineage vocabulary only
- `SubagentSession` means the durable subagent collaboration control aggregate
- `ProcessRun` and `AgentTaskRun` stay execution-instance vocabulary only
- `ConversationEvent` stays projection and audit vocabulary only
- `selector` stays the external model-selection axis
- `profile` stays the agent-program behavior axis
- internal service, model, event, and machine-contract names all use
  `subagent_session`
- agent-facing tool names remain short and capability-oriented:
  `subagent_spawn`, `subagent_send`, `subagent_wait`, `subagent_close`,
  `subagent_list`

This keeps internal semantics precise without sacrificing tool-call success
rate.

## Design Constraints

- `references/` informed the discussion, but the landed design is defined only
  by `core_matrix`, `agents/fenix`, local tests, and local behavior docs.
- External and agent-facing boundaries continue to use `public_id`; no raw
  `bigint` identifiers may leak.
- Fork, branch, thread, and checkpoint creation remain conversation-lineage
  operations only. They do not inherit, share, or reveal parent subagent
  sessions in this batch.
- Human callers may not directly address subagent conversations in this batch.
- Root interactive conversations remain fixed to `profile = "main"` in this
  batch. The model remains extensible, but no conversation override, product
  surface, or tool surface is introduced for switching the root profile.
- The runtime may statically constrain its default tool surface, and each
  frozen `profile` may mask a smaller visible tool set based on
  `profile + is_subagent + depth`.
- Child conversations may only see the same tool set as their parent or a
  strict subset.
- Nested subagents are in scope in this batch.
- The implementation must reuse existing close-control, capability-composer,
  conversation-override, and execution-snapshot infrastructure instead of
  inventing parallel protocol stacks.

## Eight Scan Passes

The repository was scanned in eight focused passes before writing this
revision. The last two passes were naming-convergence and task-sizing passes.
No new architectural areas appeared after Pass 8.

### Pass 1: Existing Subagent Surface

Scanned:

- `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- `core_matrix/app/models/subagent_run.rb`
- `core_matrix/app/services/subagents/spawn.rb`
- `core_matrix/app/models/agent_task_run.rb`
- `core_matrix/test/services/subagents/spawn_test.rb`

Findings:

- current subagent coordination is workflow-owned, not conversation-owned
- `SubagentRun` already carries nested-fanout fields (`parent_subagent_run_id`
  and `depth`) that should move to `SubagentSession`, not be dropped
- `AgentTaskRun(kind = "subagent_step")` already exists and should be reused

### Pass 2: Capability Surface And Config Contracts

Scanned:

- `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- `core_matrix/app/models/capability_snapshot.rb`
- `core_matrix/app/models/runtime_capability_contract.rb`
- `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- `core_matrix/app/services/agent_deployments/reconcile_config.rb`
- `core_matrix/app/services/agent_deployments/handshake.rb`
- `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`

Findings:

- `RuntimeCapabilityContract` is already the right projection seam for adding
  `profile_catalog`
- `CapabilitySnapshot` must persist `profile_catalog`; it cannot remain only a
  transient manifest field
- `default_config_snapshot` is the right place for `interactive.profile`,
  while `conversation_override_schema_snapshot` should stay limited to
  subagent-policy overrides in this batch
- config reconciliation already retains runtime-owned config slices and should
  extend the same pattern to `interactive.profile` and `subagents.*`
- `ComposeForConversation` currently has no conversation-aware tool filtering
  and must grow one instead of introducing a second capability plane

### Pass 3: Conversation Override, Selector State, And Turn Context

Scanned:

- `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- `core_matrix/app/services/conversations/update_override.rb`
- `core_matrix/app/models/conversation.rb`
- `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- `core_matrix/app/models/turn_execution_snapshot.rb`

Findings:

- `selector` persistence and `override_payload` persistence already give the
  correct structural model for runtime-owned configuration without persisting
  prompt text in Core Matrix
- `Conversation` still lacks an addressability axis
- root conversation profile should stay in runtime config, not on the
  conversation row, and should not become a mutable conversation override in
  this batch
- execution snapshots currently freeze model and provider context, but not
  agent-program context

### Pass 4: Fenix Runtime Manifest And Execution Boundary

Scanned:

- `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- `agents/fenix/app/services/fenix/context/build_execution_context.rb`
- `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
- `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- `agents/fenix/README.md`

Findings:

- Fenix already declares runtime config through manifest snapshots and should
  declare `profile_catalog` the same way
- the current execution context has no `profile`, `is_subagent`,
  `subagent_depth`, or `allowed_tool_names` input
- the main-agent and subagent loops can stay identical if those values are
  carried through `agent_context`
- prompt templates and model-slot switching belong inside Fenix, not in Core
  Matrix

### Pass 5: Lifecycle, Close Control, And Deletion Paths

Scanned:

- `core_matrix/app/services/agent_control/closable_resource_registry.rb`
- `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- `core_matrix/app/services/agent_control/report.rb`
- `core_matrix/app/services/conversations/archive.rb`
- `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- `core_matrix/app/services/conversations/purge_plan.rb`

Findings:

- subagent control should plug into existing `ClosableRuntimeResource`
  machinery instead of growing a new close protocol
- archive, delete, and purge already centralize cleanup decisions and should
  remain the ownership boundary
- turn interrupt must distinguish between closing a turn-scoped session and
  interrupting in-flight work on a reusable conversation-scoped session

### Pass 6: First-Draft Gap Review

Scanned:

- the first thread-named draft of this design and plan
- `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- `core_matrix/test/services/subagents/spawn_test.rb`

Findings:

- the first draft incorrectly excluded nested subagents
- the first draft incorrectly omitted `profile_catalog`
- the first draft did not carry `agent_context` through the frozen execution
  snapshot

### Pass 7: Naming Convergence

Scanned:

- `core_matrix/app/models/process_run.rb`
- `core_matrix/app/models/agent_task_run.rb`
- `core_matrix/app/models/conversation_event.rb`
- `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- both Phase 2 plan docs

Findings:

- `ProcessRun`, `AgentTaskRun`, and `ConversationEvent` already have correct
  semantics and should keep their names
- `SubagentThread` collides conceptually with `Conversation.kind = "thread"`
  and should be renamed to `SubagentSession`
- internal names should converge to `SubagentSession`, while tool names should
  stay `subagent_*`

### Pass 8: Task-Sizing And File-Anchor Review

Scanned:

- `core_matrix/app/models/runtime_capability_contract.rb`
- `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- `agents/fenix/app/services/fenix/context/build_execution_context.rb`

Findings:

- the plan should be split into smaller tasks so execution batches stay narrow
- each planned change should be anchored to existing methods, constants, or
  serializer sections to reduce exploration cost during execution
- no new architectural seams appeared after this pass

## Test Scenario Matrix

These scenarios must exist in tests before the batch is considered complete.
Keep them visible near the top of the implementation plan.

### Model And Schema Scenarios

1. `Conversation` supports
   `addressability = owner_addressable | agent_addressable`.
2. `SubagentSession` requires one owner conversation and one child
   conversation.
3. `SubagentSession` rejects owner or child conversations from a different
   installation.
4. `SubagentSession` rejects `scope = turn` without `origin_turn_id`.
5. `SubagentSession` requires `depth = 0` when
   `parent_subagent_session_id` is blank.
6. `SubagentSession` requires `depth = parent.depth + 1` when a parent
   session is present.
7. `SubagentSession` requires `profile_key`.
8. `SubagentSession` uses `ClosableRuntimeResource` and enforces close metadata
   through the same contract style as `ProcessRun`.
9. `AgentTaskRun(kind = "subagent_step")` stores one
   `subagent_session_id` and one `requested_by_turn_id`.
10. `ExecutionLease` allowlists `SubagentSession` instead of `SubagentRun`.

### Capability And Manifest Scenarios

11. runtime manifests expose `profile_catalog`.
12. `CapabilitySnapshot` persists `profile_catalog`.
13. `default_config_snapshot` includes `interactive.profile = "main"` and
    `subagents.enabled`, `subagents.allow_nested`, `subagents.max_depth`.
14. config reconciliation retains the runtime-owned `subagents` slice.
15. reserved subagent tools are injected into the base effective catalog.
16. conversation-visible tools are filtered after catalog composition.

### Tool Filtering And Nested-Subagent Scenarios

17. `subagents.enabled = false` removes the entire subagent tool family from
    the visible tool catalog.
18. `allow_nested = false` keeps subagent tools hidden in child
    conversations even when the parent conversation can use them.
19. `depth >= max_depth` hides `subagent_spawn` while leaving the rest of the
    allowed tool set intact.
20. profile masking may hide ordinary runtime tools and reserved subagent
    tools.
21. the child conversation visible tool set is always a subset of the parent
    visible tool set.
22. masked tools reject direct invocation even if the caller guesses the tool
    name.

### Conversation And Audit Scenarios

23. standard human turn-entry APIs reject writes to an
    `agent_addressable` conversation.
24. `subagent_send` rejects senders other than owner agent, subagent self, and
    system.
25. every accepted agent-authored subagent message produces one
    `ConversationEvent` audit projection on the child conversation.
26. nested subagent spawn projections record parent-session linkage and depth
    in audit payload.

### Execution Snapshot And Assignment Scenarios

27. `TurnExecutionSnapshot` freezes `agent_context`.
28. root execution snapshots freeze:
    - `profile = "main"`
    - `is_subagent = false`
    - no parent session id
29. child execution snapshots freeze:
    - `profile`
    - `is_subagent = true`
    - `subagent_session_id`
    - `parent_subagent_session_id`
    - `subagent_depth`
    - `allowed_tool_names`
30. `AgentControl::CreateExecutionAssignment` transports frozen
    `agent_context` into the mailbox payload instead of recomputing it.
31. Fenix runtime execution reads `agent_context` and keeps one shared loop for
    root and subagent execution.

### Spawn, List, Wait, And Close Scenarios

32. `subagent_spawn(scope: "turn")` creates:
    - one child conversation
    - one `SubagentSession`
    - one initial child turn and workflow dispatch
33. `subagent_spawn(scope: "conversation")` creates the same structure but
    remains reusable across later owner turns.
34. `subagent_spawn` defaults to the runtime-declared default subagent profile
    when the call omits one.
35. `subagent_list` returns only sessions owned by the current conversation
    and only by `public_id`.
36. `subagent_wait` returns immediately for a terminal durable state and
    returns a timeout result without mutating state otherwise.
37. `subagent_close` is idempotent for an already closed session.
38. a close request for a running session routes through the existing mailbox
    close-control protocol and updates `SubagentSession.close_state`.

### Lifecycle And Cleanup Scenarios

39. turn interrupt closes turn-scoped sessions created by that turn.
40. turn interrupt interrupts in-flight `subagent_step` work requested by the
    interrupted owner turn even when the session itself is
    `scope = "conversation"`.
41. turn interrupt leaves a conversation-scoped session reusable after its
    in-flight work has been interrupted.
42. archive without force rejects while any owned subagent session remains
    open.
43. archive force blocks new `spawn` and `send` requests immediately and
    issues close requests for owned open sessions.
44. delete and purge fail closed if an owner conversation still has open or
    close-pending subagent sessions.
45. purge deletes owned child subagent conversations, their task runs, mailbox
    rows, report receipts, and event projections without leaking residue across
    nested subagent trees.
46. branch, thread, checkpoint, and fork creation do not inherit or expose
    parent `SubagentSession` rows or subagent conversations.
47. no remaining code, tests, docs, migrations, or schema references mention
    `SubagentRun`, `SubagentThread`, or `subagent_thread`.

## Impacted Files And Cleanup Map

This is the minimum file set the implementation plan must cover. Delete or
rewrite obsolete surfaces; do not leave stale terminology behind.

### Core Matrix Schema And Models

- Modify: `core_matrix/app/models/capability_snapshot.rb`
  - anchors: persisted catalog fields and snapshot serialization
- Create: `core_matrix/app/models/subagent_session.rb`
  - anchors: associations, lifecycle enums, parent-depth validation, close
    contract, `public_id` exposure only
- Modify: `core_matrix/app/models/conversation.rb`
  - anchors: `addressability` enum and ownership validations
- Modify: `core_matrix/app/models/agent_task_run.rb`
  - anchors: associations, `kind` helpers, `subagent_session_id`,
    `requested_by_turn_id`
- Modify: `core_matrix/app/models/execution_lease.rb`
  - anchors: closable target allowlist
- Modify: `core_matrix/app/models/turn_execution_snapshot.rb`
  - anchors: initializer, `to_h`, reader for `agent_context`
- Delete: `core_matrix/app/models/subagent_run.rb`
- Rewrite: `core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- Rewrite: `core_matrix/db/migrate/20260324090038_create_subagent_runs.rb`
  - result: `subagent_sessions` table
- Rewrite: `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
- Regenerate: `core_matrix/db/schema.rb`

### Core Matrix Services And Queries

- Modify: `core_matrix/app/models/runtime_capability_contract.rb`
  - anchors: `initialize`, `agent_plane`, `contract_payload`,
    `conversation_payload`, `reserved_core_matrix_tool?`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
  - anchors: `CORE_MATRIX_TOOL_CATALOG`, `call`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
  - anchors: `call`
- Modify: `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
  - anchors: refresh path for conversation-visible tools
- Modify: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
  - anchors: registration payload intake
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
  - anchors: capability response rendering
- Modify: `core_matrix/app/services/agent_deployments/register.rb`
  - anchors: capability snapshot persistence
- Modify: `core_matrix/app/services/agent_deployments/handshake.rb`
  - anchors: manifest comparison and persistence
- Modify: `core_matrix/app/services/agent_deployments/reconcile_config.rb`
  - anchors: retention of runtime-owned `subagents` config
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
  - anchors: bundled manifest registration
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
  - anchors: `call`, `execution_identity`, new `agent_context` builder
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
  - anchors: `base_payload`
- Modify: `core_matrix/app/services/agent_control/closable_resource_registry.rb`
  - anchors: resource registration table
- Modify: `core_matrix/app/services/agent_control/create_resource_close_request.rb`
  - anchors: closable dispatch path
- Modify: `core_matrix/app/services/agent_control/apply_close_outcome.rb`
  - anchors: durable close-state update
- Modify: `core_matrix/app/services/agent_control/report.rb`
  - anchors: terminal report reconciliation
- Create: `core_matrix/app/services/subagent_sessions/spawn.rb`
- Create: `core_matrix/app/services/subagent_sessions/send_message.rb`
- Create: `core_matrix/app/services/subagent_sessions/list_for_conversation.rb`
- Create: `core_matrix/app/services/subagent_sessions/wait.rb`
- Create: `core_matrix/app/services/subagent_sessions/request_close.rb`
- Create: `core_matrix/app/services/subagent_sessions/validate_addressability.rb`
- Create: `core_matrix/app/services/turns/start_agent_turn.rb`
- Modify: `core_matrix/app/services/conversations/update_override.rb`
  - anchors: subagent-policy override validation and rejection of root profile
    overrides
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
- Modify: `core_matrix/app/services/conversation_events/project.rb`
  - anchors: event projection call path
- Delete: `core_matrix/app/services/subagents/spawn.rb`

### Fenix Runtime Surface

- Modify: `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
  - anchors: `CONFIG_SCHEMA_SNAPSHOT`,
    `CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT`, `DEFAULT_CONFIG_SNAPSHOT`, `call`,
    `agent_plane`
- Modify: `agents/fenix/app/services/fenix/context/build_execution_context.rb`
  - anchors: `call`
- Modify: `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
  - anchors: `call`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
  - anchors: `call`
- Modify: `agents/fenix/README.md`

### Tests

- Create: `core_matrix/test/models/subagent_session_test.rb`
- Create: `core_matrix/test/services/subagent_sessions/spawn_test.rb`
- Create: `core_matrix/test/services/subagent_sessions/send_message_test.rb`
- Create: `core_matrix/test/services/subagent_sessions/wait_test.rb`
- Create: `core_matrix/test/services/subagent_sessions/request_close_test.rb`
- Create: `core_matrix/test/services/turns/start_agent_turn_test.rb`
- Modify: `core_matrix/test/models/agent_task_run_test.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/models/execution_lease_test.rb`
- Modify: `core_matrix/test/models/capability_snapshot_test.rb`
- Modify: `core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`
- Modify: `core_matrix/test/services/runtime_capabilities/compose_for_conversation_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Modify: `core_matrix/test/services/conversations/archive_test.rb`
- Modify: `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- Modify: `core_matrix/test/services/conversations/purge_deleted_test.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
- Modify: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Modify: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Modify: `core_matrix/test/requests/agent_api/capabilities_test.rb`
- Modify: `core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `core_matrix/test/test_helper.rb`
- Delete: `core_matrix/test/models/subagent_run_test.rb`
- Delete: `core_matrix/test/services/subagents/spawn_test.rb`
- Modify: `agents/fenix/test/integration/runtime_flow_test.rb`
- Modify: `agents/fenix/test/integration/external_runtime_pairing_test.rb`
- Modify: `agents/fenix/test/test_helper.rb`

### Behavior Docs

- Rewrite: `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- Modify: `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- Modify: `agents/fenix/README.md`

## Approved Design

### 1. Core Architecture

Subagents become conversation-first collaboration sessions, not workflow-owned
runtime rows.

Each subagent consists of two durable records:

1. one child `Conversation`
2. one `SubagentSession` control row that points at that child conversation and
   its owner conversation

The child conversation reuses existing conversation infrastructure:

- lineage
- transcript storage
- turn orchestration
- workflow orchestration
- canonical store references
- runtime binding to the same execution environment as the owner conversation

`SubagentSession` exists only to hold control-plane facts that do not belong
on `Conversation` itself:

- owner conversation
- origin turn
- scope
- frozen profile
- parent-session linkage
- nested depth
- durable open or closed availability
- close-control state
- last known execution status

### 2. Configuration Axes

The runtime model now has two explicit axes:

- `selector`
  - owned by Core Matrix selector resolution
  - expresses external provider and model choice
- `profile`
  - owned by the agent program
  - expresses prompt building, behavioral responsibility, default tool
    masking, and nested-subagent masking

Rules:

- `selector` and `profile` are orthogonal
- Fenix may internally switch model slots while running a profile, but that
  stays runtime behavior
- root interactive conversation remains fixed to `profile = "main"` in this
  batch
- subagent profile freezes at `subagent_spawn` time and never changes for that
  session
- runtime manifests may declare any profile catalog keys, but `main` must
  exist

### 3. Capability Contract And Runtime Manifest

The capability handshake gains one new agent-program surface:

- `profile_catalog`

The runtime config surface gains:

- `interactive.profile`
- `subagents.enabled`
- `subagents.allow_nested`
- `subagents.max_depth`
- optional default subagent profile metadata

These values must round-trip through:

- Fenix manifest generation
- `CapabilitySnapshot`
- registration and handshake
- bundled runtime registration
- capability response payloads
- conversation runtime-contract refresh

The conversation override surface in this batch remains narrower:

- `subagents.*` may participate in conversation-level capability policy
- `interactive.profile` remains fixed by runtime defaults and is not exposed as
  a mutable conversation override

### 4. Tool Visibility And Nested Policy

Tool visibility follows one path only:

1. compose the base effective catalog from environment tools, agent tools, and
   reserved Core Matrix tools
2. apply conversation capability policy
3. apply frozen profile masking declared by the runtime and enforced by Core
   Matrix

Nested-subagent policy is enforced by the visible tool set:

- if `subagents.enabled = false`, hide the whole subagent tool family
- if `allow_nested = false`, child conversations do not see
  `subagent_spawn`
- if `depth >= max_depth`, child conversations do not see `subagent_spawn`
- child-visible tool sets are always a subset of parent-visible tool sets

Reserved subagent tools are platform-owned and may not be overridden by agent
programs or execution environments, but they may be hidden by policy.

### 5. Conversation Addressability And Audit

Subagent conversations are `agent_addressable`, not user-addressable.

Consequences:

- normal human turn-entry services must reject writes
- subagent messages must flow through one dedicated service boundary
- sender types must be constrained to owner agent, subagent self, and system
- accepted writes produce `ConversationEvent` audit projections

Transcript-bearing content continues to use normal message storage. Audit
metadata should stay light and reuse `ConversationEvent` rather than inventing
an additional event log.

### 6. `SubagentSession` Contract

`SubagentSession` is the only durable subagent control aggregate. Its fields
should remain limited to control-plane facts:

- `conversation_id`
- `owner_conversation_id`
- `origin_turn_id`
- `scope = turn | conversation`
- `profile_key`
- `canonical_name`
- `nickname`
- `parent_subagent_session_id`
- `depth`
- `lifecycle_state = open | close_requested | closed`
- `last_known_status = idle | running | waiting | completed | failed | interrupted`
- close-control metadata from `ClosableRuntimeResource`

Key invariants:

- owner and child conversations share installation
- `profile_key` is always present
- `depth = 0` when there is no parent session
- `depth = parent.depth + 1` when there is a parent session
- a deleted owner conversation may not retain open or close-pending sessions

### 7. Machine Contract Surface

Tool names stay short:

- `subagent_spawn`
- `subagent_send`
- `subagent_wait`
- `subagent_close`
- `subagent_list`

Machine-facing payload fields use the converged internal name:

- `subagent_session_id`
- `parent_subagent_session_id`
- `subagent_depth`

This split is intentional. Internal semantics stay precise while agent-facing
tool names stay short and conventional.

### 8. Execution Snapshot And Assignment Payload

`TurnExecutionSnapshot` must freeze `agent_context` so that mailbox assignment
creation becomes a transport step instead of a recomputation step.

`agent_context` must include:

- `profile`
- `is_subagent`
- `subagent_session_id`
- `parent_subagent_session_id`
- `subagent_depth`
- `allowed_tool_names`
- optional owner-conversation identifiers by `public_id`

Fenix then reads `agent_context` from one place and keeps a single shared loop
for root and subagent execution.

### 9. Spawn, Send, List, Wait, And Close

`subagent_spawn` must:

- resolve the requested or default profile
- enforce nested policy from the parent conversation contract
- create the child conversation
- create the `SubagentSession`
- append the initial delegated message
- allocate child turn, workflow, and `AgentTaskRun(kind = "subagent_step")`

`subagent_send` must:

- validate addressability
- validate sender kind
- append transcript-bearing content
- project audit events

`subagent_list` must:

- return only sessions owned by the current conversation
- expose only `public_id` identifiers

`subagent_wait` and `subagent_close` must:

- rely on durable state
- reuse existing close-control infrastructure
- remain idempotent for terminal states

### 10. Lifecycle, Archive, Delete, And Purge

Lifecycle ownership stays anchored on the owner conversation.

- turn-scoped sessions are closed when the origin turn is interrupted or ends
  in a closing path
- conversation-scoped sessions survive interrupted work but not owner archive,
  delete, or purge
- archive without force blocks on open sessions
- archive force requests closes and blocks new `spawn` and `send`
- delete and purge fail closed if session residue remains
- purge removes owned child conversations, task runs, mailbox rows, receipts,
  and event projections depth-first

Fork, branch, thread, and checkpoint creation remain lineage-only and do not
inherit or reveal subagent sessions.

### 11. Fenix Public API Change

Core Matrix and Fenix public API changes in this batch are:

- manifest exposes `profile_catalog`
- manifest config snapshots expose `interactive.profile` and `subagents.*`
- execution assignments expose `agent_context`

Fenix remains the owner of:

- prompt building
- prompt-template selection
- internal model-slot switching
- profile semantics that explain which tools should be visible for a given
  profile, subagent flag, and depth

Core Matrix remains the owner of:

- conversation ownership
- capability projection
- visible-tool enforcement
- lifecycle and close semantics
- durable session state

### 12. Orthogonality And Reuse Check

This design is intentionally orthogonal to the rest of the system.

Reused primitives:

- `Conversation`
- `AgentTaskRun`
- `TurnExecutionSnapshot`
- `RuntimeCapabilityContract`
- `RuntimeCapabilities::ComposeForConversation`
- `ConversationEvent`
- `ConversationCloseOperation`
- `ClosableRuntimeResource`
- `AgentControlMailboxItem`

New first-class concept introduced in this batch:

- `SubagentSession`

Rejected alternatives:

- no second capability plane
- no Core Matrix prompt-template ownership
- no `SubagentRun` compatibility layer
- no `SubagentThread` terminology alongside `Conversation.kind = "thread"`
- no separate event-sourcing stack for subagent audit

## Acceptance Conditions

The design is only considered landed when all of the following are true:

- `SubagentRun` is removed from code, docs, tests, migrations, and schema
- `SubagentThread` and `subagent_thread` are removed from code, docs, tests,
  and machine contracts
- `SubagentSession` is the only durable subagent control aggregate
- root interactive profile is fixed to `main`
- nested subagents work through child conversations plus parent-depth policy
- `profile_catalog` persists through manifest, snapshot, registration,
  capability response, and execution
- `agent_context` freezes on `TurnExecutionSnapshot`
- Fenix main-agent and subagent execution share one loop
- archive, delete, and purge do not leak nested subagent residue
- tool visibility is composed once and filtered once; no parallel tool plane
  exists
