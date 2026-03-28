# Profile-Aware Conversation-First Subagent Sessions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to
> implement this plan task-by-task.

**Goal:** Replace workflow-owned `SubagentRun` coordination with
profile-aware, conversation-first `SubagentSession` control, runtime-declared
profile catalogs, nested-subagent policy filtering, and owner-conversation
lifecycle handling that archives, deletes, and purges without leaking runtime
residue.

**Architecture:** Reuse the existing Core Matrix primitives instead of
inventing a parallel stack. `Conversation` remains the transcript and lineage
aggregate, `SubagentSession` becomes the durable control row,
`AgentTaskRun(kind = "subagent_step")` stays the execution instance,
`TurnExecutionSnapshot` freezes the runtime-facing `agent_context`,
`RuntimeCapabilityContract` stays the manifest formatter, and mailbox close
control plus `ConversationEvent` projection are extended to the new session
model. Fenix remains the owner of prompt building, profile catalogs, and
internal model-slot switching.

**Tech Stack:** Ruby on Rails (`core_matrix` and `agents/fenix`), Active
Record, mailbox control plane, Minitest, behavior docs in
`core_matrix/docs/behavior`, plan docs in `docs/plans`

---

## Execution Rules

- This is a structural rewrite. Do not keep compatibility wrappers.
- Execute straight through from Task 1 to the final verification task. Do not
  stop for intermediate design confirmations unless a new blocker invalidates
  the approved design.
- Use TDD for every batch: write failing test, run it, implement minimal fix,
  rerun, commit.
- Prefer reusing existing infrastructure:
  - `ClosableRuntimeResource`
  - `AgentTaskRun`
  - `TurnExecutionSnapshot`
  - `ConversationEvent`
  - `ConversationCloseOperation`
  - `AgentControlMailboxItem`
  - `RuntimeCapabilityContract`
  - `RuntimeCapabilities::ComposeForConversation`
  - `Conversations::UpdateOverride`
- Keep all external and agent-facing references on `public_id`.
- Nested subagents are in scope for this batch.
- Root interactive conversations remain fixed to `profile = "main"` in this
  batch.
- Do not add a `personality` axis in this batch.
- Internal model, service, event, and machine-contract names must use
  `SubagentSession` / `subagent_session`.
- Agent-facing tool names stay short:
  `subagent_spawn`, `subagent_send`, `subagent_wait`, `subagent_close`,
  `subagent_list`.

## Mandatory Scenario Gate

Before shipping, all of these scenario families must have explicit tests:

- schema and model contracts
- capability and manifest contract updates
- conversation-aware tool filtering
- profile catalog projection
- root profile freeze to `main`
- spawn, send, list, wait, and close flows
- nested-subagent depth and parentage
- execution snapshot `agent_context`
- Fenix execution-context parsing
- conversation addressability guard
- turn interrupt behavior for both `scope = turn` and
  `scope = conversation`
- archive, delete, finalize, and purge behavior across nested subagent trees
- fork non-inheritance
- grep-based removal of `SubagentRun`, `SubagentThread`, and
  `subagent_thread` from code, docs, tests, and schema

## Known File Targets With Anchors

Start from this list and keep it current while implementing.

### Core Matrix

- `core_matrix/app/models/subagent_session.rb`
  - anchors: associations, lifecycle enums, parent-depth validation, close
    contract
- `core_matrix/app/models/conversation.rb`
  - anchors: `addressability` enum, ownership validation helpers
- `core_matrix/app/models/agent_task_run.rb`
  - anchors: associations, `kind` helpers, `subagent_session_id`,
    `requested_by_turn_id`
- `core_matrix/app/models/execution_lease.rb`
  - anchors: closable target allowlist
- `core_matrix/app/models/capability_snapshot.rb`
  - anchors: persisted snapshot fields
- `core_matrix/app/models/runtime_capability_contract.rb`
  - anchors: `initialize`, `agent_plane`, `contract_payload`,
    `conversation_payload`, `reserved_core_matrix_tool?`
- `core_matrix/app/models/turn_execution_snapshot.rb`
  - anchors: `initialize`, `to_h`, `identity`, new `agent_context` reader
- `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
  - anchors: `CORE_MATRIX_TOOL_CATALOG`, `call`
- `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
  - anchors: `call`
- `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
  - anchors: runtime-contract refresh path
- `core_matrix/app/services/agent_deployments/handshake.rb`
  - anchors: manifest comparison and persistence
- `core_matrix/app/services/agent_deployments/register.rb`
  - anchors: snapshot creation
- `core_matrix/app/services/agent_deployments/reconcile_config.rb`
  - anchors: retention of runtime-owned config slices
- `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
  - anchors: bundled registration payload
- `core_matrix/app/controllers/agent_api/registrations_controller.rb`
  - anchors: request parsing
- `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
  - anchors: capability response rendering
- `core_matrix/app/services/workflows/build_execution_snapshot.rb`
  - anchors: `call`, `execution_identity`, new `agent_context` builder
- `core_matrix/app/services/agent_control/create_execution_assignment.rb`
  - anchors: `base_payload`
- `core_matrix/app/services/conversation_events/project.rb`
  - anchors: `call`
- `core_matrix/app/services/subagent_sessions/spawn.rb`
- `core_matrix/app/services/subagent_sessions/send_message.rb`
- `core_matrix/app/services/subagent_sessions/list_for_conversation.rb`
- `core_matrix/app/services/subagent_sessions/wait.rb`
- `core_matrix/app/services/subagent_sessions/request_close.rb`
- `core_matrix/app/services/subagent_sessions/validate_addressability.rb`
- `core_matrix/app/services/turns/start_agent_turn.rb`
- `core_matrix/app/services/turns/start_user_turn.rb`
- `core_matrix/app/services/turns/queue_follow_up.rb`
- `core_matrix/app/services/agent_control/closable_resource_registry.rb`
- `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- `core_matrix/app/services/agent_control/report.rb`
- `core_matrix/app/services/conversations/update_override.rb`
  - anchors: subagent-policy override validation and rejection of
    `interactive.profile` overrides
- `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- `core_matrix/app/services/conversations/request_resource_closes.rb`
- `core_matrix/app/services/conversations/progress_close_requests.rb`
- `core_matrix/app/services/conversations/archive.rb`
- `core_matrix/app/services/conversations/create_thread.rb`
- `core_matrix/app/services/conversations/finalize_deletion.rb`
- `core_matrix/app/services/conversations/purge_plan.rb`
- `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- `core_matrix/app/services/workflows/create_for_turn.rb`
- `core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- `core_matrix/db/migrate/20260324090038_create_subagent_runs.rb`
  - result: `subagent_sessions` table
- `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
- `core_matrix/db/schema.rb`

### Fenix

- `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
  - anchors: `CONFIG_SCHEMA_SNAPSHOT`,
    `CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT`, `DEFAULT_CONFIG_SNAPSHOT`, `call`,
    `agent_plane`
- `agents/fenix/app/services/fenix/context/build_execution_context.rb`
  - anchors: `call`
- `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
  - anchors: `call`
- `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
  - anchors: `call`
- `agents/fenix/README.md`

### Cleanup Targets

- delete `core_matrix/app/models/subagent_run.rb`
- delete `core_matrix/app/services/subagents/spawn.rb`
- delete `core_matrix/test/models/subagent_run_test.rb`
- delete `core_matrix/test/services/subagents/spawn_test.rb`
- remove all stale `SubagentThread` / `subagent_thread` references from:
  - plan docs
  - behavior docs
  - schema
  - tests
  - event names

## Task 1: Rewrite The Schema Around `SubagentSession`

**Files and locations**

- `core_matrix/db/migrate/20260324090038_create_subagent_runs.rb`
  - rewrite into `subagent_sessions`
- `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
  - add `addressability`, `subagent_session_id`, `requested_by_turn_id`
- `core_matrix/app/models/subagent_session.rb`
  - new model
- `core_matrix/app/models/conversation.rb`
  - `addressability`
- `core_matrix/app/models/agent_task_run.rb`
  - new association columns
- `core_matrix/test/models/subagent_session_test.rb`
- `core_matrix/test/models/conversation_test.rb`
- `core_matrix/test/models/agent_task_run_test.rb`

**Write failing tests**

- `Conversation.addressability`
- `SubagentSession` validation rules
- parent-depth invariants
- `profile_key`
- `AgentTaskRun` support for `subagent_session_id` and `requested_by_turn_id`

**Run**

```bash
cd core_matrix
bin/rails test \
  test/models/subagent_session_test.rb \
  test/models/conversation_test.rb \
  test/models/agent_task_run_test.rb
```

**Implement**

- replace the old subagent migration with a `subagent_sessions` table
- add `addressability` to `conversations`
- add `subagent_session_id` and `requested_by_turn_id` to `agent_task_runs`
- define associations and validations
- regenerate `db/schema.rb`

## Task 2: Move Close-Control Identity From `SubagentRun` To `SubagentSession`

**Files and locations**

- `core_matrix/app/models/subagent_session.rb`
  - close metadata and lifecycle enums
- `core_matrix/app/models/execution_lease.rb`
  - allowlist
- `core_matrix/app/services/agent_control/closable_resource_registry.rb`
  - resource registry table
- `core_matrix/test/models/execution_lease_test.rb`

**Write failing tests**

- `SubagentSession` participates in `ClosableRuntimeResource`
- `ExecutionLease` accepts `SubagentSession` and rejects `SubagentRun`

**Run**

```bash
cd core_matrix
bin/rails test \
  test/models/subagent_session_test.rb \
  test/models/execution_lease_test.rb
```

**Implement**

- move close-control columns and behavior to `SubagentSession`
- update lease allowlists and model support
- remove any schema- or model-level `SubagentRun` assumptions

## Task 3: Persist Profile Catalog On `CapabilitySnapshot`

**Files and locations**

- `core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- `core_matrix/app/models/capability_snapshot.rb`
  - persisted fields
- `core_matrix/app/services/agent_deployments/register.rb`
  - snapshot creation
- `core_matrix/app/services/agent_deployments/handshake.rb`
  - persistence path
- `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
  - bundled registration
- `core_matrix/test/models/capability_snapshot_test.rb`
- `core_matrix/test/services/agent_deployments/handshake_test.rb`
- `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`

**Write failing tests**

- `profile_catalog` round-trips through snapshot persistence
- bundled runtime registration preserves `profile_catalog`

**Run**

```bash
cd core_matrix
bin/rails test \
  test/models/capability_snapshot_test.rb \
  test/services/agent_deployments/handshake_test.rb \
  test/services/installations/register_bundled_agent_runtime_test.rb
```

**Implement**

- add persisted `profile_catalog`
- extend registration and handshake persistence paths

## Task 4: Extend `RuntimeCapabilityContract` For Profiles And Subagent Policy

**Files and locations**

- `core_matrix/app/models/runtime_capability_contract.rb`
  - `initialize`, `agent_plane`, `contract_payload`,
    `conversation_payload`
- `core_matrix/app/services/agent_deployments/reconcile_config.rb`
  - retain `interactive.profile` and `subagents.*`
- `core_matrix/app/controllers/agent_api/registrations_controller.rb`
  - request parsing
- `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
  - capability response
- `core_matrix/test/requests/agent_api/capabilities_test.rb`
- `core_matrix/test/integration/agent_registration_contract_test.rb`

**Write failing tests**

- `agent_plane` exposes `profile_catalog`
- default config exposes `interactive.profile` and `subagents.*`
- conversation override schema exposes `subagents.*` but not
  `interactive.profile`
- config reconciliation retains `subagents`

**Run**

```bash
cd core_matrix
bin/rails test \
  test/requests/agent_api/capabilities_test.rb \
  test/integration/agent_registration_contract_test.rb \
  test/services/agent_deployments/handshake_test.rb
```

**Implement**

- extend the runtime capability contract payload
- update registration and capability response rendering
- keep root interactive profile fixed to `main`
- keep `interactive.profile` out of mutable conversation overrides

## Task 5: Inject Reserved Subagent Tools Into The Base Catalog

**Files and locations**

- `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
  - `CORE_MATRIX_TOOL_CATALOG`, `call`
- `core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`

**Write failing tests**

- base effective catalog contains reserved `subagent_*` tools
- reserved tool names cannot be overridden by runtime tools

**Run**

```bash
cd core_matrix
bin/rails test \
  test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb
```

**Implement**

- define the reserved subagent tool family in the base catalog composer
- keep tool names short and agent-facing

## Task 6: Filter Conversation-Visible Tools By Policy And Profile

**Files and locations**

- `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
  - `call`
- `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
  - contract refresh path
- `core_matrix/app/services/conversations/update_override.rb`
  - subagent-policy overrides only
- `core_matrix/test/services/runtime_capabilities/compose_for_conversation_test.rb`

**Write failing tests**

- `subagents.enabled = false` hides the whole subagent tool family
- `allow_nested = false` hides `subagent_spawn` for child conversations
- `depth >= max_depth` hides `subagent_spawn`
- visible child tools are a subset of visible parent tools
- masked tools reject direct invocation

**Run**

```bash
cd core_matrix
bin/rails test \
  test/services/runtime_capabilities/compose_for_conversation_test.rb
```

**Implement**

- add conversation-aware tool filtering
- apply runtime policy first, then frozen profile masking
- ensure the conversation-visible tool set is the only runtime-facing tool set

## Task 7: Teach Fenix To Declare Profiles And Config Defaults

**Files and locations**

- `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
  - `CONFIG_SCHEMA_SNAPSHOT`,
    `CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT`, `DEFAULT_CONFIG_SNAPSHOT`, `call`,
    `agent_plane`
- `agents/fenix/test/integration/external_runtime_pairing_test.rb`
- `agents/fenix/README.md`

**Write failing tests**

- manifest exposes `profile_catalog`
- manifest default config exposes `interactive.profile` and `subagents.*`
- manifest conversation override schema exposes only subagent-policy overrides

**Run**

```bash
cd agents/fenix
bin/rails test test/integration/external_runtime_pairing_test.rb
```

**Implement**

- add `profile_catalog` to the manifest
- expose `interactive.profile` through default config and expose only
  `subagents.*` through the conversation override schema
- keep `interactive.profile` in defaults only and out of mutable overrides
- document that prompt building stays inside Fenix

## Task 8: Freeze `agent_context` On `TurnExecutionSnapshot`

**Files and locations**

- `core_matrix/app/services/workflows/build_execution_snapshot.rb`
  - `call`, `execution_identity`, new `agent_context` builder
- `core_matrix/app/models/turn_execution_snapshot.rb`
  - initializer, readers, `to_h`
- `core_matrix/app/services/agent_control/create_execution_assignment.rb`
  - `base_payload`
- `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- `core_matrix/test/services/workflows/create_for_turn_test.rb`

**Write failing tests**

- root snapshots freeze `profile = "main"` and `is_subagent = false`
- child snapshots freeze profile, session ids, depth, and `allowed_tool_names`
- mailbox assignment payload transports frozen `agent_context`

**Run**

```bash
cd core_matrix
bin/rails test \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/workflows/create_for_turn_test.rb
```

**Implement**

- extend execution snapshots with `agent_context`
- keep assignment creation as transport only

## Task 9: Teach Fenix To Read `agent_context`

**Files and locations**

- `agents/fenix/app/services/fenix/context/build_execution_context.rb`
  - `call`
- `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
  - `call`
- `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
  - `call`
- `agents/fenix/test/integration/runtime_flow_test.rb`

**Write failing tests**

- execution payload parsing exposes `agent_context`
- the same runtime flow works for root and subagent assignments
- `prepare_turn` can see `profile` and `allowed_tool_names`

**Run**

```bash
cd agents/fenix
bin/rails test test/integration/runtime_flow_test.rb
```

**Implement**

- parse `agent_context`
- keep one shared execution flow
- expose `profile`, `is_subagent`, depth, and tool visibility to prompt
  preparation

## Task 10: Add Addressability Guard And `subagent_send`

**Files and locations**

- `core_matrix/app/services/subagent_sessions/validate_addressability.rb`
- `core_matrix/app/services/subagent_sessions/send_message.rb`
- `core_matrix/app/services/turns/start_user_turn.rb`
- `core_matrix/app/services/turns/queue_follow_up.rb`
- `core_matrix/app/services/conversation_events/project.rb`
- `core_matrix/test/services/subagent_sessions/send_message_test.rb`
- `core_matrix/test/services/turns/start_user_turn_test.rb`
- `core_matrix/test/services/turns/queue_follow_up_test.rb`

**Write failing tests**

- human callers cannot append to `agent_addressable` conversations
- only owner agent, subagent self, and system senders are accepted
- successful sends append transcript and project audit events

**Run**

```bash
cd core_matrix
bin/rails test \
  test/services/subagent_sessions/send_message_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb
```

**Implement**

- add addressability guard
- implement `SubagentSessions::SendMessage`
- route human turn entry through the same guard
- project sender audit through `ConversationEvent`

## Task 11: Implement `subagent_spawn`, `subagent_list`, And `StartAgentTurn`

**Files and locations**

- `core_matrix/app/services/subagent_sessions/spawn.rb`
- `core_matrix/app/services/subagent_sessions/list_for_conversation.rb`
- `core_matrix/app/services/turns/start_agent_turn.rb`
- `core_matrix/app/services/conversations/create_thread.rb`
- `core_matrix/app/services/workflows/create_for_turn.rb`
- `core_matrix/test/services/subagent_sessions/spawn_test.rb`
- `core_matrix/test/services/turns/start_agent_turn_test.rb`
- `core_matrix/test/services/workflows/create_for_turn_test.rb`

**Write failing tests**

- turn-scoped spawn creates one child conversation and one `SubagentSession`
- conversation-scoped spawn creates a reusable session
- nested spawn records `parent_subagent_session_id` and `depth`
- spawn resolves explicit or default profile
- initial child work is scheduled through `AgentTaskRun(kind = "subagent_step")`
- list only returns sessions owned by the current conversation

**Run**

```bash
cd core_matrix
bin/rails test \
  test/services/subagent_sessions/spawn_test.rb \
  test/services/turns/start_agent_turn_test.rb \
  test/services/workflows/create_for_turn_test.rb
```

**Implement**

- enforce nested policy before creation
- resolve requested or default profile from the runtime-declared catalog
- create the child conversation and `SubagentSession`
- append the initial delegated message
- allocate child turn, workflow, and task work through existing services
- delete `core_matrix/app/services/subagents/spawn.rb`

## Task 12: Implement `subagent_wait` And `subagent_close`

**Files and locations**

- `core_matrix/app/services/subagent_sessions/wait.rb`
- `core_matrix/app/services/subagent_sessions/request_close.rb`
- `core_matrix/app/services/agent_control/closable_resource_registry.rb`
- `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- `core_matrix/app/services/agent_control/report.rb`
- `core_matrix/test/services/subagent_sessions/wait_test.rb`
- `core_matrix/test/services/subagent_sessions/request_close_test.rb`
- `core_matrix/test/services/agent_control/report_test.rb`

**Write failing tests**

- wait short-circuits on terminal durable state
- wait times out cleanly
- close is idempotent
- close reports update session close state, lifecycle state, and
  `last_known_status`

**Run**

```bash
cd core_matrix
bin/rails test \
  test/services/subagent_sessions/wait_test.rb \
  test/services/subagent_sessions/request_close_test.rb \
  test/services/agent_control/report_test.rb
```

**Implement**

- add `SubagentSession` to the closable-resource registry
- route close requests and reports through existing mailbox close control
- implement durable wait semantics only

## Task 13: Fold Nested Session Trees Into Interrupt, Archive, Delete, And Purge

**Files and locations**

- `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- `core_matrix/app/services/conversations/request_resource_closes.rb`
- `core_matrix/app/services/conversations/progress_close_requests.rb`
- `core_matrix/app/services/conversations/archive.rb`
- `core_matrix/app/services/conversations/finalize_deletion.rb`
- `core_matrix/app/services/conversations/purge_plan.rb`
- `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- `core_matrix/test/services/conversations/archive_test.rb`
- `core_matrix/test/services/conversations/purge_deleted_test.rb`

**Write failing tests**

- turn interrupt closes turn-scoped sessions created by that turn
- turn interrupt interrupts in-flight work requested by that turn on reusable
  sessions
- archive without force blocks on open sessions
- archive force blocks new spawn and send requests
- delete and purge fail closed until nested residue is gone

**Run**

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/conversations/archive_test.rb \
  test/services/conversations/purge_deleted_test.rb
```

**Implement**

- recurse owned session trees for force-close and purge
- keep fork and branch lineage semantics unchanged
- ensure no nested residue leaks across purge

## Task 14: Rewrite Behavior Docs And Remove Stale Terminology

**Files and locations**

- `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- `agents/fenix/README.md`

**Update docs after code lands**

- `SubagentSession` is the durable control aggregate
- tool names remain `subagent_*`
- `profile_catalog` belongs to the runtime manifest and capability snapshot
- root interactive profile is fixed to `main`
- `agent_context` is part of the frozen execution snapshot
- conversation-visible tools are filtered per conversation
- Fenix owns prompt building and internal model-slot switching

**Run stale-term greps**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "SubagentRun|subagent run" core_matrix agents/fenix docs
rg -n "SubagentThread|subagent_thread" core_matrix agents/fenix docs
```

## Final Verification

### Core Matrix

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

### Fenix

```bash
cd agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
```

### Final Greps

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "SubagentRun|subagent_runs" core_matrix agents/fenix docs
rg -n "SubagentThread|subagent_thread" core_matrix agents/fenix docs
rg -n "do not add nested subagent|does not add nested subagent|out of scope.*nested" docs core_matrix agents/fenix
rg -n "profile_catalog|interactive\\.profile|subagents\\.|agent_context|subagent_session_id|parent_subagent_session_id" core_matrix agents/fenix docs
```

Expected:

- no stale `SubagentRun` implementation references remain
- no stale `SubagentThread` terminology remains
- no stale design text says nested subagents are out of scope
- the new profile-aware session contract appears in code, tests, and docs

## Completion Checklist

- `SubagentRun` is fully removed
- `SubagentThread` and `subagent_thread` are fully removed
- `SubagentSession` is the only durable subagent control aggregate
- profile metadata is runtime-declared and frozen into execution
- root interactive profile remains fixed to `main`
- nested subagent policy is enforced through conversation-visible tool
  filtering
- Fenix reuses one loop for root and subagent execution
- archive, delete, and purge handle nested session trees without residue
- behavior docs, plan docs, and tests use consistent terminology

## Self-Review Rubric Before Execution

Check this plan once more before implementing:

- completeness: every scenario family from the gate has a task owner
- orthogonality: no task introduces a second capability plane or second close
  protocol
- reuse: new code layers on `Conversation`, `AgentTaskRun`,
  `TurnExecutionSnapshot`, `RuntimeCapabilityContract`, and
  `ClosableRuntimeResource`
- naming: internal names use `SubagentSession`; tool names stay `subagent_*`
- task size: each task is small enough to execute without reopening broad
  design questions
- file anchors: each task lists the existing files and anchor sections that
  should be touched
