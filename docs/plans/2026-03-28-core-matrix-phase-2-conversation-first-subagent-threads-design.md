# Core Matrix Phase 2 Design: Profile-Aware Conversation-First Subagent Threads

Use this design document before starting the Phase 2 restructuring batch that
replaces workflow-owned `SubagentRun` rows with profile-aware,
conversation-first subagent threads.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
4. `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
5. `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
6. `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
7. `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
8. `docs/plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md`

## Purpose

Phase 2 currently models subagents as workflow-owned runtime rows and exposes
`subagent_spawn` as an ordinary runtime tool.

That shape is materially worse than the approved target:

- subagents do not have their own conversation transcript
- subagent lifecycle is anchored to workflow nodes instead of conversation
  ownership
- capability contracts cannot express profile-aware subagent behavior or
  nested-subagent policy cleanly
- the machine-facing execution payload does not tell the agent program which
  profile or subagent context it is running under
- close, archive, delete, and purge semantics have to special-case
  workflow-owned residue

This design replaces that model with a conversation-first architecture:

- every subagent owns a child `Conversation`
- a new `SubagentThread` row is the durable control aggregate
- `AgentTaskRun(kind = "subagent_step")` remains the reusable execution
  instance
- subagent behavior is driven by runtime-declared `profile` metadata, not by
  Core Matrix-owned prompt templates
- existing capability contracts, config snapshots, conversation override
  infrastructure, execution snapshots, mailbox control, and close
  reconciliation infrastructure stay in place

This batch is intentionally breaking:

- no compatibility shims
- no dual-track `SubagentRun` and `SubagentThread` model
- no data backfill
- no legacy docs kept alive for transition wording

## Design Constraints

- `references/` informed the discussion, but the landed design is defined only
  by `core_matrix`, `agents/fenix`, local tests, and local behavior docs.
- External and agent-facing boundaries continue to use `public_id`; no raw
  `bigint` identifiers may leak.
- Fork, branch, thread, and checkpoint creation remain conversation-lineage
  operations only. They do not inherit, share, or reveal parent subagent
  threads in this batch.
- Human callers may not directly address subagent conversations in this batch.
- `selector` remains the model-selection axis. `profile` is a separate
  agent-program axis and does not replace selector resolution.
- This batch does not add a Codex-style `personality` axis. Future tone or
  `SOUL.md` work remains agent-program configuration, not kernel design.
- Root interactive conversations remain fixed to `profile = "main"` in this
  batch. The internal model should remain extensible, but no product or tool
  surface is introduced for switching the root profile.
- The implementation must reuse existing close-control, capability-composer,
  conversation-override, and execution-snapshot infrastructure instead of
  inventing parallel protocol stacks.

## Six Scan Passes

The repository was scanned in six focused passes before writing this revision.
The sixth pass surfaced the last missing architectural seam:
`agent_context` must freeze on `TurnExecutionSnapshot` rather than being
assembled ad hoc inside mailbox assignment creation. No new architectural areas
appeared after the sixth pass.

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
  and `depth`) that should move to `SubagentThread`, not be dropped
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
- `default_config_snapshot` and `conversation_override_schema_snapshot` are
  already the right places for runtime-declared configuration
- config reconciliation currently retains `interactive`, `model_slots`, and
  `model_roles`; this batch must extend the same pattern to `subagents`
- `ComposeForConversation` currently has no conversation-aware tool filtering
  and must grow one instead of introducing a second capability plane

### Pass 3: Conversation Override, Selector State, And Turn Context

Scanned:

- `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- `core_matrix/app/services/conversations/update_override.rb`
- `core_matrix/app/models/conversation.rb`
- `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`

Findings:

- `selector` persistence and `override_payload` persistence already give the
  correct structural model for runtime-owned configuration without persisting
  prompt text in Core Matrix
- `Conversation` still lacks an addressability axis
- root conversation profile should stay in runtime config, not on the
  conversation row
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
- the current execution context has no `profile`, `is_subagent`, or
  `allowed_tool_names` input
- the main-agent and subagent loops can stay identical if those values are
  carried through `agent_context`
- prompt templates and model-slot switching belong inside Fenix, not in Core
  Matrix

### Pass 5: Existing Design, Cleanup Map, And Nested-Subagent Gaps

Scanned:

- `docs/plans/2026-03-28-core-matrix-phase-2-conversation-first-subagent-threads-design.md`
- `docs/plans/2026-03-28-core-matrix-phase-2-plan-conversation-first-subagent-threads.md`
- `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- `core_matrix/test/services/subagents/spawn_test.rb`

Findings:

- the first design draft incorrectly excluded nested subagent spawning from the
  batch
- the first design draft incorrectly dropped parent and depth from the durable
  control aggregate
- the first implementation plan did not account for `profile_catalog`,
  `subagents.*` policy, Fenix manifest changes, or `agent_context`

### Pass 6: Runtime Contract Refresh And Execution Snapshot Freeze

Scanned:

- `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
- `core_matrix/test/services/runtime_capabilities/compose_for_conversation_test.rb`
- `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- `core_matrix/app/models/turn_execution_snapshot.rb`
- `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`

Findings:

- conversation runtime contracts are already read through one service boundary,
  so conversation-aware tool filtering should extend that path rather than
  bypass it
- `agent_context` must freeze on `TurnExecutionSnapshot`
- mailbox assignment creation should read the frozen `agent_context` rather
  than recomputing runtime-visible tool policy on the fly

## Test Scenario Matrix

These scenarios must exist in tests before the batch is considered complete.
Keep them visible at the top of the implementation plan and land them in this
approximate order.

### Model And Schema Scenarios

1. `Conversation` supports
   `addressability = owner_addressable | agent_addressable`.
2. `SubagentThread` requires one owner conversation and one child
   conversation.
3. `SubagentThread` rejects owner or child conversations from a different
   installation.
4. `SubagentThread` rejects `scope = turn` without `origin_turn_id`.
5. `SubagentThread` requires `depth = 0` when `parent_subagent_thread_id` is
   blank.
6. `SubagentThread` requires `depth = parent.depth + 1` when a parent thread
   exists.
7. `SubagentThread` requires `profile_key`.
8. `SubagentThread` uses `ClosableRuntimeResource` and enforces close metadata
   pairings without inventing a second close-state machine.
9. `AgentTaskRun(kind = "subagent_step")` may reference one
   `subagent_thread_id` and one `requested_by_turn_id` in addition to its child
   conversation turn.
10. `ExecutionLease` accepts `SubagentThread` instead of `SubagentRun` in the
    leased-resource allowlist.

### Capability, Manifest, And Config Scenarios

11. capability snapshots and Fenix manifests expose `profile_catalog`.
12. `default_config_snapshot` exposes:
    - `interactive.selector`
    - `interactive.profile`
    - `subagents.enabled`
    - `subagents.allow_nested`
    - `subagents.max_depth`
    - optional `subagents.default_profile`
13. `conversation_override_schema_snapshot` exposes subagent-policy keys but
    does not expose root interactive profile switching in this batch.
14. config reconciliation retains `subagents` when the next schema still
    declares it.
15. reserved Core Matrix subagent tools always appear in the base effective
    catalog and runtime snapshots may not redefine them.
16. conversation runtime contracts filter that base catalog through
    conversation policy and profile mask before returning visible tools.

### Root Profile And Spawn Scenarios

17. root interactive conversations resolve to `profile = "main"` without
    storing a separate root-profile column.
18. `subagent_spawn(scope: "turn")` creates:
    - one child conversation with `kind = "thread"`
    - `purpose = "interactive"`
    - `addressability = "agent_addressable"`
    - one `SubagentThread`
    - `profile_key`
    - `depth`
    - one initial child turn/workflow/task dispatch
19. `subagent_spawn(scope: "conversation")` creates the same structure but
    remains reusable across later owner turns.
20. `subagent_spawn` defaults to the runtime-declared default subagent profile
    when the call omits one.
21. `subagent_list` returns only threads owned by the current conversation and
    only by `public_id`.

### Tool Filtering And Nested-Subagent Scenarios

22. `subagents.enabled = false` removes the entire subagent tool family from
    the visible tool catalog.
23. `allow_nested = false` keeps subagent tools hidden in child conversations
    even when the parent conversation can use them.
24. `depth >= max_depth` hides `subagent_spawn` while leaving the rest of the
    allowed tool set intact.
25. profile mask may hide ordinary runtime tools and reserved subagent tools.
26. the child conversation visible tool set is always a subset of the parent
    visible tool set.
27. masked tools reject direct invocation even if the caller guesses the tool
    name.

### Message Entry And Audit Scenarios

28. standard human turn-entry APIs reject writes to an
    `agent_addressable` conversation.
29. `subagent_send` rejects senders other than:
    - the owner conversation agent
    - the subagent itself
    - the system
30. every accepted agent-authored subagent message produces one
    `ConversationEvent` audit projection on the child conversation.
31. nested subagent spawn projections record parent thread linkage and depth in
    audit payload.

### Execution Snapshot And Assignment Scenarios

32. `TurnExecutionSnapshot` freezes `agent_context`.
33. root execution snapshots freeze:
    - `profile = "main"`
    - `is_subagent = false`
    - no parent thread id
34. child execution snapshots freeze:
    - `profile`
    - `is_subagent = true`
    - `subagent_thread_id`
    - `parent_subagent_thread_id`
    - `subagent_depth`
    - `allowed_tool_names`
35. `AgentControl::CreateExecutionAssignment` transports frozen `agent_context`
    into the mailbox payload instead of recomputing it.
36. Fenix runtime execution reads `agent_context` and keeps one shared loop for
    root and subagent execution.

### Wait, Close, And Notification Scenarios

37. `subagent_wait` returns immediately for a terminal durable state and
    returns a timeout result without mutating state otherwise.
38. `subagent_close` is idempotent for an already closed thread.
39. a close request for a running subagent thread routes through the existing
    mailbox close-control protocol and updates `SubagentThread.close_state`.
40. terminal close reports re-enter
    `Conversations::ReconcileCloseOperation` through the owner conversation.
41. owner-conversation event projection records `subagent_thread.opened`,
    `subagent_thread.completed`, `subagent_thread.failed`, and
    `subagent_thread.closed` through `ConversationEvent`.

### Turn Interrupt, Archive, Delete, And Purge Scenarios

42. turn interrupt closes turn-scoped subagent threads created by that turn.
43. turn interrupt interrupts in-flight `subagent_step` work requested by the
    interrupted owner turn even when the thread itself is
    `scope = "conversation"`.
44. turn interrupt leaves a conversation-scoped thread reusable after its
    in-flight work has been interrupted.
45. archive without force rejects while any owned subagent thread remains
    open.
46. archive force blocks new `spawn` and `send` requests immediately and
    issues close requests for owned open subagent threads.
47. delete and purge fail closed if an owner conversation still has open or
    close-pending subagent threads.
48. purge deletes owned child subagent conversations, their task runs, mailbox
    rows, report receipts, and event projections without leaking residue across
    nested subagent trees.

### Lineage And Cleanup Scenarios

49. branch, thread, checkpoint, and fork creation do not inherit or expose
    parent `SubagentThread` rows or subagent conversations.
50. no remaining code, tests, docs, migrations, or schema references mention
    `SubagentRun`.
51. no remaining design text in the current plan docs says nested subagents are
    out of scope for this batch.

## Impacted Files And Cleanup Map

This is the minimum file set the implementation plan must cover. Delete or
rewrite obsolete surfaces; do not leave stale terminology behind.

### Core Matrix Schema And Models

- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Create: `core_matrix/app/models/subagent_thread.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/models/execution_lease.rb`
- Modify: `core_matrix/app/models/turn_execution_snapshot.rb`
- Delete: `core_matrix/app/models/subagent_run.rb`
- Rewrite: `core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- Rewrite: `core_matrix/db/migrate/20260324090038_create_subagent_runs.rb`
- Rewrite: `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
- Regenerate: `core_matrix/db/schema.rb`

### Core Matrix Services And Queries

- Create: `core_matrix/app/services/subagent_threads/spawn.rb`
- Create: `core_matrix/app/services/subagent_threads/send_message.rb`
- Create: `core_matrix/app/services/subagent_threads/list_for_conversation.rb`
- Create: `core_matrix/app/services/subagent_threads/wait.rb`
- Create: `core_matrix/app/services/subagent_threads/request_close.rb`
- Create: `core_matrix/app/services/subagent_threads/validate_addressability.rb`
- Create: `core_matrix/app/services/turns/start_agent_turn.rb`
- Modify: `core_matrix/app/models/runtime_capability_contract.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- Modify: `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
- Modify: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify: `core_matrix/app/services/agent_deployments/register.rb`
- Modify: `core_matrix/app/services/agent_deployments/handshake.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `core_matrix/app/services/agent_control/closable_resource_registry.rb`
- Modify: `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- Modify: `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Modify: `core_matrix/app/services/agent_control/report.rb`
- Modify: `core_matrix/app/services/conversations/update_override.rb`
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
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Delete: `core_matrix/app/services/subagents/spawn.rb`

### Fenix Runtime Surface

- Modify: `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Modify: `agents/fenix/app/services/fenix/context/build_execution_context.rb`
- Modify: `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `agents/fenix/README.md`

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

Subagents become conversation-scoped collaboration threads, not workflow-owned
runtime rows.

Each subagent consists of two durable records:

1. one child `Conversation`
2. one `SubagentThread` control row that points at that child conversation and
   its owner conversation

The child conversation reuses existing conversation infrastructure:

- conversation lineage
- transcript storage
- turn and workflow orchestration
- canonical store reference
- runtime binding to the same execution environment as the owner conversation

`SubagentThread` exists only to hold control-plane facts that do not belong on
`Conversation` itself:

- owner conversation
- origin turn
- scope
- frozen profile
- parent thread linkage
- nested depth
- durable open or closed availability
- close-control state
- last known execution status

This keeps transcript history and control lifecycle orthogonal instead of
putting both concerns on one model.

### 2. Configuration Axes

The runtime model now has two explicit axes in this batch:

- `selector`
  - owned by Core Matrix selector resolution
  - expresses external provider and model choice
- `profile`
  - owned by the agent program
  - expresses prompt building, behavioral responsibility, default tool
    filtering, and nested-subagent masking

This batch explicitly does not add a third `personality` axis.

Rules:

- `selector` and `profile` are orthogonal
- Fenix may internally switch model slots while running a profile, but that
  behavior remains inside Fenix
- root interactive conversations use `profile = "main"`
- subagent profile selection happens only at spawn time
- existing subagent threads never change profile after creation

### 3. Capability Contract And Profile Catalog

`RuntimeCapabilityContract` and the Fenix manifest grow one new
runtime-declared metadata section:

- `profile_catalog`

Each catalog entry must be lightweight and stable:

- `key`
- `display_name`
- `description`
- optional advisory metadata such as `spawnable` or
  `recommended_for_subagents`

The catalog does not expose prompt text or template internals.

`default_config_snapshot` becomes the runtime-owned default configuration
surface for this batch. It should declare at least:

- `interactive.selector`
- `interactive.profile`
- `subagents.enabled`
- `subagents.allow_nested`
- `subagents.max_depth`
- optional `subagents.default_profile`

`conversation_override_schema_snapshot` remains the runtime-owned override
surface. In this batch it should continue to expose selector override and may
also expose subagent policy override keys, but it must not expose root
interactive profile switching.

Config reconciliation should continue to retain runtime-owned configuration
keys across capability refresh. `interactive` already remains retained through
the existing merge behavior; this batch adds `subagents` to the retained-key
family.

### 4. Conversation Rules

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

### 5. `SubagentThread` Contract

`SubagentThread` is the durable control aggregate. Its fields should be kept
minimal and should reuse existing close-control conventions:

- `public_id`
- `installation_id`
- `owner_conversation_id`
- `conversation_id`
- `origin_turn_id`
- `scope = "turn" | "conversation"`
- `profile_key`
- optional `requested_role_or_slot`
- optional `nickname`
- optional `parent_subagent_thread_id`
- `depth`
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

Rules:

- root subagent threads use `depth = 0`
- child threads use `depth = parent.depth + 1`
- `parent_subagent_thread_id` never crosses conversation ownership or
  installation boundaries
- `profile_key` is always required

Deliberately not carried forward from `SubagentRun`:

- `batch_key`
- `coordination_key`
- `terminal_summary_artifact_id`

Those fields were tied to workflow fan-out semantics and do not belong in the
conversation-first control model.

### 6. Tool Visibility Pipeline

Tool visibility now has one path, not separate root versus subagent catalogs.

The pipeline is:

1. build the base effective catalog from:
   - `ExecutionEnvironment`
   - agent runtime tool catalog
   - reserved Core Matrix tools
2. apply conversation capability policy from the runtime config and any
   allowed conversation override
3. apply the frozen profile mask using:
   - `profile`
   - `is_subagent`
   - `subagent_depth`
   - parent visible tool set when a parent thread exists

Rules:

- reserved Core Matrix subagent tools remain platform-owned and may not be
  redefined by runtime snapshots
- reserved tools may still be hidden by policy or masked by profile
- masked tools are omitted from the visible catalog and also reject direct
  invocation if called by guessed name
- child visible tools must always be a subset of the parent visible tools
- nested subagent availability is controlled by:
  - `subagents.enabled`
  - `subagents.allow_nested`
  - `subagents.max_depth`
  - profile mask

### 7. Execution Snapshot And Assignment Contract

`agent_context` becomes part of the frozen execution contract.

`TurnExecutionSnapshot` grows:

- `agent_context`

The frozen `agent_context` must include at least:

- `profile`
- `is_subagent`
- `subagent_thread_id`
- `parent_subagent_thread_id`
- `subagent_depth`
- `allowed_tool_names`
- `addressability`
- `owner_conversation_id` when the turn belongs to a subagent thread

Rules:

- root turns freeze `profile = "main"` and `is_subagent = false`
- subagent turns freeze their thread profile and nested metadata
- mailbox assignment creation transports the frozen `agent_context`; it does
  not recompute conversation-visible tools at dispatch time

This keeps retries, manual resume, and recovery-time execution working against
one stable runtime contract.

### 8. Fenix Responsibility Boundary

Fenix owns:

- `profile_catalog`
- prompt building
- profile-specific system prompt or `SOUL.md` composition
- internal model-slot switching
- profile-based tool filtering rules

Core Matrix owns:

- selector resolution
- capability snapshot persistence
- conversation-visible tool projection
- nested depth and ownership enforcement
- lifecycle, close, archive, delete, and purge

This batch keeps one shared Fenix loop for root and subagent execution.
Subagent behavior comes entirely from frozen `agent_context`, not from a second
executor class.

### 9. Spawn, Send, Wait, And Close

Reserved tool names:

- `subagent_spawn`
- `subagent_send`
- `subagent_wait`
- `subagent_close`
- `subagent_list`

`subagent_spawn` must:

- resolve the requested or default profile from the runtime-declared catalog
- enforce nested policy before creation
- create or reuse the child conversation through `Conversations::CreateThread`
- create the `SubagentThread`
- append the initial delegated input
- allocate child turn and workflow work through `Turns::StartAgentTurn`,
  `Workflows::CreateForTurn`, and `AgentTaskRun(kind = "subagent_step")`

`subagent_send` must:

- validate sender kind
- validate visible-tool policy for the target conversation
- append agent-authored input to the child conversation
- allocate one new child turn/work item when needed

`subagent_wait` and `subagent_close` must reuse the existing close-control
protocol and durable state transitions.

### 10. Message Entry And Audit

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

### 11. Lifecycle, Archive, Delete, And Purge

`SubagentThread` must plug into existing close-control infrastructure rather
than inventing a second lifecycle protocol.

Reuse:

- `ClosableRuntimeResource`
- `AgentControl::CreateResourceCloseRequest`
- `AgentControlMailboxItem`
- `AgentControl::ApplyCloseOutcome`
- `Conversations::ReconcileCloseOperation`

Lifecycle rules:

- turn-scoped threads close when the owning turn is interrupted or ends under
  close conditions
- conversation-scoped threads stay reusable across owner turns until explicitly
  closed or conversation lifecycle demands closure
- archive without force blocks on any owned open subagent thread
- archive force and delete request close on the entire owned subagent tree
- purge fails closed if any owned thread still has open or close-pending
  residue
- nested-subagent purge deletes owned child conversations and mailbox residue
  depth-first

### 12. Explicit Non-Goals

This batch does not do any of the following:

- introduce a `personality` axis
- expose product-level root profile switching
- share or inherit live subagent threads across fork or branch operations
- create a Core Matrix-owned cross-runtime profile taxonomy beyond reserving
  `main`
- move prompt template ownership out of Fenix

### 13. Orthogonality And Reuse Rationale

This design stays orthogonal with the existing system because it reuses the
already-approved primitives instead of creating a second stack:

- `Conversation` still owns transcript and lineage
- `SubagentThread` owns only control-plane facts
- `TurnExecutionSnapshot` remains the one frozen runtime-facing execution
  contract
- `AgentTaskRun` remains the execution instance
- `RuntimeCapabilityContract` remains the one manifest and capability
  formatter
- `ComposeForConversation` remains the conversation runtime-contract entry
  point
- `ConversationEvent` remains the lightweight audit and lifecycle projection
  surface
- close control, archive, delete, and purge reuse existing conversation
  lifecycle infrastructure

The only new first-class domain concept is `SubagentThread`. Everything else
extends existing seams.
