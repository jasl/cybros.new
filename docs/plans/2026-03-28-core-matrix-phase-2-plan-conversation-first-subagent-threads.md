# Profile-Aware Conversation-First Subagent Threads Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace workflow-owned `SubagentRun` coordination with
profile-aware, conversation-first `SubagentThread` control, runtime-declared
profile catalogs, nested-subagent policy filtering, and owner-conversation
lifecycle handling that archives, deletes, and purges without leaking runtime
residue.

**Architecture:** Reuse the existing Core Matrix primitives instead of
inventing a parallel stack. `Conversation` remains the transcript and lineage
aggregate, `SubagentThread` becomes the durable control row, `AgentTaskRun(kind
= "subagent_step")` stays the execution instance, `TurnExecutionSnapshot`
freezes the runtime-facing `agent_context`, `RuntimeCapabilityContract` stays
the manifest formatter, and mailbox close control plus `ConversationEvent`
projection are extended to the new thread model. Fenix remains the owner of
prompt building, profile catalogs, and internal model-slot switching.

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
- After every major task, run:
  - `rg -n "SubagentRun|subagent_runs" core_matrix`
  - `rg -n "profile_catalog|interactive\\.profile|subagents\\." core_matrix agents/fenix`
  - `rg -n "agent_context" core_matrix agents/fenix`
- Keep all external and agent-facing references on `public_id`.
- Nested subagents are in scope for this batch.
- Root interactive conversations remain fixed to `profile = "main"` in this
  batch.
- Do not add a `personality` axis in this batch.

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
- grep-based removal of `SubagentRun` from code, docs, tests, and schema

## Known File Targets

Start from this list and keep it current while implementing.

### Core Matrix

- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Create: `core_matrix/app/models/subagent_thread.rb`
- Create: `core_matrix/app/services/subagent_threads/spawn.rb`
- Create: `core_matrix/app/services/subagent_threads/send_message.rb`
- Create: `core_matrix/app/services/subagent_threads/list_for_conversation.rb`
- Create: `core_matrix/app/services/subagent_threads/wait.rb`
- Create: `core_matrix/app/services/subagent_threads/request_close.rb`
- Create: `core_matrix/app/services/subagent_threads/validate_addressability.rb`
- Create: `core_matrix/app/services/turns/start_agent_turn.rb`
- Create: `core_matrix/test/models/subagent_thread_test.rb`
- Create: `core_matrix/test/services/subagent_threads/spawn_test.rb`
- Create: `core_matrix/test/services/subagent_threads/send_message_test.rb`
- Create: `core_matrix/test/services/subagent_threads/wait_test.rb`
- Create: `core_matrix/test/services/subagent_threads/request_close_test.rb`
- Create: `core_matrix/test/services/turns/start_agent_turn_test.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/models/execution_lease.rb`
- Modify: `core_matrix/app/models/runtime_capability_contract.rb`
- Modify: `core_matrix/app/models/turn_execution_snapshot.rb`
- Modify: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- Modify: `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `core_matrix/app/services/agent_control/closable_resource_registry.rb`
- Modify: `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- Modify: `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Modify: `core_matrix/app/services/agent_control/report.rb`
- Modify: `core_matrix/app/services/agent_deployments/register.rb`
- Modify: `core_matrix/app/services/agent_deployments/handshake.rb`
- Modify: `core_matrix/app/services/agent_deployments/reconcile_config.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
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
- Modify: `core_matrix/db/migrate/20260324090038_create_subagent_runs.rb`
- Modify: `core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- Modify: `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
- Modify: `core_matrix/db/schema.rb`
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
- Modify: `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- Modify: `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- Delete: `core_matrix/app/models/subagent_run.rb`
- Delete: `core_matrix/app/services/subagents/spawn.rb`
- Delete: `core_matrix/test/models/subagent_run_test.rb`
- Delete: `core_matrix/test/services/subagents/spawn_test.rb`

### Fenix

- Modify: `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Modify: `agents/fenix/app/services/fenix/context/build_execution_context.rb`
- Modify: `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `agents/fenix/test/integration/runtime_flow_test.rb`
- Modify: `agents/fenix/test/integration/external_runtime_pairing_test.rb`
- Modify: `agents/fenix/test/test_helper.rb`
- Modify: `agents/fenix/README.md`

## Task 1: Rewrite The Schema Around `SubagentThread`

**Files:**
- Create: `core_matrix/app/models/subagent_thread.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/models/execution_lease.rb`
- Modify: `core_matrix/db/migrate/20260324090038_create_subagent_runs.rb`
- Modify: `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
- Modify: `core_matrix/db/schema.rb`
- Create: `core_matrix/test/models/subagent_thread_test.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/models/agent_task_run_test.rb`
- Modify: `core_matrix/test/models/execution_lease_test.rb`
- Delete: `core_matrix/test/models/subagent_run_test.rb`

**Step 1: Write the failing tests**

Add model coverage for:

- `Conversation.addressability`
- `SubagentThread` validation rules
- `SubagentThread` parent and depth rules
- `SubagentThread.profile_key`
- `SubagentThread` close metadata rules through `ClosableRuntimeResource`
- `AgentTaskRun` support for `subagent_thread_id` and `requested_by_turn_id`
- `ExecutionLease` allowlist swapping `SubagentRun` for `SubagentThread`

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/subagent_thread_test.rb \
  test/models/conversation_test.rb \
  test/models/agent_task_run_test.rb \
  test/models/execution_lease_test.rb
```

Expected: FAIL because `SubagentThread`, `Conversation.addressability`, and
the new `AgentTaskRun` references do not exist yet.

**Step 3: Write the minimal implementation**

- replace the old subagent migration with a `subagent_threads` table
- add `addressability` to `conversations`
- add `subagent_thread_id` and `requested_by_turn_id` to `agent_task_runs`
- move close-control columns from `SubagentRun` onto `SubagentThread`
- keep `parent_subagent_thread_id`, `depth`, and `profile_key` on
  `SubagentThread`
- update associations and validations
- remove `SubagentRun` from the codebase

**Step 4: Regenerate schema**

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:migrate
```

Expected: PASS and `db/schema.rb` reflects `subagent_threads` with no
`subagent_runs` table.

**Step 5: Run tests to verify they pass**

Run the same `bin/rails test` command from Step 2 and confirm PASS.

**Step 6: Grep for stale schema-level references**

Run:

```bash
cd core_matrix
rg -n "SubagentRun|subagent_runs" app/models test/models db/migrate db/schema.rb
```

Expected: no remaining matches outside intentionally untouched files for later
tasks.

**Step 7: Commit**

```bash
git add core_matrix/app/models/subagent_thread.rb \
  core_matrix/app/models/conversation.rb \
  core_matrix/app/models/agent_task_run.rb \
  core_matrix/app/models/execution_lease.rb \
  core_matrix/db/migrate/20260324090038_create_subagent_runs.rb \
  core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb \
  core_matrix/db/schema.rb \
  core_matrix/test/models/subagent_thread_test.rb \
  core_matrix/test/models/conversation_test.rb \
  core_matrix/test/models/agent_task_run_test.rb \
  core_matrix/test/models/execution_lease_test.rb \
  core_matrix/test/models/subagent_run_test.rb
git commit -m "refactor: replace subagent runs with subagent threads"
```

## Task 2: Extend Capability Contracts For Profiles And Subagent Policy

**Files:**
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/app/models/runtime_capability_contract.rb`
- Modify: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- Modify: `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
- Modify: `core_matrix/app/services/agent_deployments/register.rb`
- Modify: `core_matrix/app/services/agent_deployments/handshake.rb`
- Modify: `core_matrix/app/services/agent_deployments/reconcile_config.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- Modify: `core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`
- Modify: `core_matrix/test/services/runtime_capabilities/compose_for_conversation_test.rb`
- Modify: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `core_matrix/test/requests/agent_api/capabilities_test.rb`
- Modify: `core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `core_matrix/test/models/capability_snapshot_test.rb`

**Step 1: Write the failing tests**

Add coverage for:

- reserved Core Matrix subagent tools are injected into the base effective
  catalog
- `profile_catalog` round-trips through capability refresh and handshake
- `default_config_snapshot` includes `interactive.profile` and `subagents.*`
- config reconciliation retains `subagents`
- conversation runtime contracts filter visible tools by subagent policy
- masked tools are omitted from visible conversation tool lists

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb \
  test/services/runtime_capabilities/compose_for_conversation_test.rb \
  test/services/agent_deployments/handshake_test.rb \
  test/requests/agent_api/capabilities_test.rb \
  test/integration/agent_registration_contract_test.rb \
  test/models/capability_snapshot_test.rb
```

Expected: FAIL because the contract does not yet carry profile metadata or
conversation-aware tool filtering.

**Step 3: Write the minimal implementation**

- add `profile_catalog` to `RuntimeCapabilityContract`
- persist `profile_catalog` on `CapabilitySnapshot`
- define the reserved subagent tool family in
  `CORE_MATRIX_TOOL_CATALOG`
- extend registration, handshake, and bundled-runtime registration to accept
  and compare `profile_catalog`
- make `ComposeForConversation` conversation-aware and policy-aware
- treat runtime-visible conversation tools as a filtered projection, not the
  raw base effective catalog
- extend config reconciliation to retain `subagents`

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Grep for stale capability assumptions**

Run:

```bash
cd core_matrix
rg -n "default_tool_catalog\\(|conversation_override_schema_snapshot|default_config_snapshot" test app
```

Expected: touched call sites now account for `profile_catalog`,
`interactive.profile`, and `subagents.*`.

**Step 6: Commit**

```bash
git add core_matrix/app/models/runtime_capability_contract.rb \
  core_matrix/app/models/capability_snapshot.rb \
  core_matrix/app/controllers/agent_api/registrations_controller.rb \
  core_matrix/app/controllers/agent_api/capabilities_controller.rb \
  core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb \
  core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb \
  core_matrix/app/services/conversations/refresh_runtime_contract.rb \
  core_matrix/app/services/agent_deployments/register.rb \
  core_matrix/app/services/agent_deployments/handshake.rb \
  core_matrix/app/services/agent_deployments/reconcile_config.rb \
  core_matrix/app/services/installations/register_bundled_agent_runtime.rb \
  core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb \
  core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb \
  core_matrix/test/services/runtime_capabilities/compose_for_conversation_test.rb \
  core_matrix/test/services/agent_deployments/handshake_test.rb \
  core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb \
  core_matrix/test/requests/agent_api/capabilities_test.rb \
  core_matrix/test/integration/agent_registration_contract_test.rb \
  core_matrix/test/models/capability_snapshot_test.rb
git commit -m "feat: add profile-aware capability contracts"
```

## Task 3: Teach Fenix To Declare Profiles And Read `agent_context`

**Files:**
- Modify: `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Modify: `agents/fenix/app/services/fenix/context/build_execution_context.rb`
- Modify: `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `agents/fenix/test/integration/runtime_flow_test.rb`
- Modify: `agents/fenix/test/integration/external_runtime_pairing_test.rb`
- Modify: `agents/fenix/test/test_helper.rb`
- Modify: `agents/fenix/README.md`

**Step 1: Write the failing tests**

Add coverage for:

- manifest exposes `profile_catalog`
- manifest default config includes `interactive.profile` and `subagents.*`
- execution payload parsing exposes `agent_context`
- the same runtime flow works for root and subagent assignments
- `prepare_turn` can see `profile` and `allowed_tool_names`

**Step 2: Run tests to verify they fail**

Run:

```bash
cd agents/fenix
bin/rails test \
  test/integration/runtime_flow_test.rb \
  test/integration/external_runtime_pairing_test.rb
```

Expected: FAIL because Fenix does not yet declare profile metadata or parse
`agent_context`.

**Step 3: Write the minimal implementation**

- add `profile_catalog` to the pairing manifest
- add `interactive.profile` and `subagents.*` to the runtime config schema and
  defaults
- parse `agent_context` in `BuildExecutionContext`
- keep the shared execution flow intact; only enrich the context
- update README wording to state that profile selection and prompt building are
  Fenix-owned runtime behavior

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/runtime/pairing_manifest.rb \
  agents/fenix/app/services/fenix/context/build_execution_context.rb \
  agents/fenix/app/services/fenix/hooks/prepare_turn.rb \
  agents/fenix/app/services/fenix/runtime/execute_assignment.rb \
  agents/fenix/test/integration/runtime_flow_test.rb \
  agents/fenix/test/integration/external_runtime_pairing_test.rb \
  agents/fenix/test/test_helper.rb \
  agents/fenix/README.md
git commit -m "feat: add fenix profile catalog and agent context"
```

## Task 4: Freeze `agent_context` On The Execution Snapshot

**Files:**
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/app/models/turn_execution_snapshot.rb`
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write the failing tests**

Add coverage for:

- root execution snapshots freeze `agent_context.profile = "main"`
- subagent execution snapshots freeze `profile`, `is_subagent`, parent thread
  id, depth, and `allowed_tool_names`
- mailbox assignment payload reuses the frozen `agent_context`

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/workflows/create_for_turn_test.rb
```

Expected: FAIL because `TurnExecutionSnapshot` does not yet expose
`agent_context`.

**Step 3: Write the minimal implementation**

- extend `BuildExecutionSnapshot`
- extend `TurnExecutionSnapshot`
- source allowed tool names from the conversation runtime contract
- keep mailbox assignment creation as a transport layer only

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/workflows/build_execution_snapshot.rb \
  core_matrix/app/models/turn_execution_snapshot.rb \
  core_matrix/app/services/agent_control/create_execution_assignment.rb \
  core_matrix/test/services/workflows/build_execution_snapshot_test.rb \
  core_matrix/test/services/workflows/create_for_turn_test.rb \
  core_matrix/test/test_helper.rb
git commit -m "feat: freeze agent context on execution snapshots"
```

## Task 5: Add The Subagent Conversation Guard And Message Services

**Files:**
- Create: `core_matrix/app/services/subagent_threads/validate_addressability.rb`
- Create: `core_matrix/app/services/subagent_threads/send_message.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/services/conversation_events/project.rb`
- Create: `core_matrix/test/services/subagent_threads/send_message_test.rb`
- Modify: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Modify: `core_matrix/test/services/turns/queue_follow_up_test.rb`

**Step 1: Write the failing tests**

Cover:

- human callers cannot append turns or transcript to an
  `agent_addressable` conversation
- only `owner_agent`, `subagent_self`, and `system` senders are accepted
- successful sends append transcript and project an audit event

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/subagent_threads/send_message_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb
```

Expected: FAIL because the guard service and subagent send service do not
exist.

**Step 3: Write the minimal implementation**

- add the addressability guard
- implement `SubagentThreads::SendMessage`
- route human turn entry and queued follow-up entry through the same guard
- project sender audit through `ConversationEvent`
- keep transcript-bearing content on normal `Message` rows

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/subagent_threads/validate_addressability.rb \
  core_matrix/app/services/subagent_threads/send_message.rb \
  core_matrix/app/services/turns/start_user_turn.rb \
  core_matrix/app/services/turns/queue_follow_up.rb \
  core_matrix/app/models/conversation.rb \
  core_matrix/app/services/conversation_events/project.rb \
  core_matrix/test/services/subagent_threads/send_message_test.rb \
  core_matrix/test/services/turns/start_user_turn_test.rb \
  core_matrix/test/services/turns/queue_follow_up_test.rb
git commit -m "feat: guard agent-addressable conversation writes"
```

## Task 6: Implement `subagent_spawn` And `subagent_list` With Profile Resolution

**Files:**
- Create: `core_matrix/app/services/subagent_threads/spawn.rb`
- Create: `core_matrix/app/services/subagent_threads/list_for_conversation.rb`
- Create: `core_matrix/app/services/turns/start_agent_turn.rb`
- Modify: `core_matrix/app/services/conversations/create_thread.rb`
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Create: `core_matrix/test/services/subagent_threads/spawn_test.rb`
- Create: `core_matrix/test/services/turns/start_agent_turn_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Delete: `core_matrix/app/services/subagents/spawn.rb`
- Delete: `core_matrix/test/services/subagents/spawn_test.rb`

**Step 1: Write the failing tests**

Cover:

- turn-scoped spawn creates one child conversation and one `SubagentThread`
- conversation-scoped spawn creates a reusable thread
- nested spawn records `parent_subagent_thread_id` and `depth`
- spawn resolves explicit or default profile
- initial child work is scheduled through `AgentTaskRun(kind = "subagent_step")`
- list only returns threads owned by the current conversation

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/subagent_threads/spawn_test.rb \
  test/services/turns/start_agent_turn_test.rb \
  test/services/workflows/create_for_turn_test.rb
```

Expected: FAIL because the new spawn path, nested policy, and list path are
not wired.

**Step 3: Write the minimal implementation**

- resolve the requested or default profile from the runtime-declared catalog
- enforce nested policy before creation
- create the child conversation
- create the `SubagentThread`
- append the initial delegated message
- allocate child turn, workflow, and task work through `Turns::StartAgentTurn`,
  `Workflows::CreateForTurn`, and `AgentTaskRun`
- implement `ListForConversation`
- remove the old `Subagents::Spawn` service

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Grep for stale spawn services**

Run:

```bash
cd core_matrix
rg -n "Subagents::Spawn|subagents/spawn|SubagentRun.create!" app test
```

Expected: no remaining matches.

**Step 6: Commit**

```bash
git add core_matrix/app/services/subagent_threads/spawn.rb \
  core_matrix/app/services/subagent_threads/list_for_conversation.rb \
  core_matrix/app/services/turns/start_agent_turn.rb \
  core_matrix/app/services/conversations/create_thread.rb \
  core_matrix/app/services/workflows/create_for_turn.rb \
  core_matrix/app/services/agent_control/create_execution_assignment.rb \
  core_matrix/test/services/subagent_threads/spawn_test.rb \
  core_matrix/test/services/turns/start_agent_turn_test.rb \
  core_matrix/test/services/workflows/create_for_turn_test.rb \
  core_matrix/app/services/subagents/spawn.rb \
  core_matrix/test/services/subagents/spawn_test.rb
git commit -m "feat: spawn profile-aware subagent threads"
```

## Task 7: Implement `subagent_wait` And `subagent_close` Using Existing Close Control

**Files:**
- Create: `core_matrix/app/services/subagent_threads/wait.rb`
- Create: `core_matrix/app/services/subagent_threads/request_close.rb`
- Modify: `core_matrix/app/services/agent_control/closable_resource_registry.rb`
- Modify: `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Modify: `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- Modify: `core_matrix/app/services/agent_control/report.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
- Create: `core_matrix/test/services/subagent_threads/wait_test.rb`
- Create: `core_matrix/test/services/subagent_threads/request_close_test.rb`

**Step 1: Write the failing tests**

Cover:

- wait short-circuits on terminal durable state
- wait times out cleanly
- close is idempotent
- close reports update `SubagentThread.close_state`, `lifecycle_state`, and
  `last_known_status`
- terminal close still re-enters owner conversation reconciliation

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/subagent_threads/wait_test.rb \
  test/services/subagent_threads/request_close_test.rb \
  test/services/agent_control/report_test.rb
```

Expected: FAIL because the registry and close report logic still reference
`SubagentRun`.

**Step 3: Write the minimal implementation**

- add `SubagentThread` to the closable-resource registry
- route close requests and close reports through the existing mailbox protocol
- implement `SubagentThreads::Wait` against durable state only

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/subagent_threads/wait.rb \
  core_matrix/app/services/subagent_threads/request_close.rb \
  core_matrix/app/services/agent_control/closable_resource_registry.rb \
  core_matrix/app/services/agent_control/create_resource_close_request.rb \
  core_matrix/app/services/agent_control/apply_close_outcome.rb \
  core_matrix/app/services/agent_control/report.rb \
  core_matrix/test/services/subagent_threads/wait_test.rb \
  core_matrix/test/services/subagent_threads/request_close_test.rb \
  core_matrix/test/services/agent_control/report_test.rb
git commit -m "feat: add wait and close for subagent threads"
```

## Task 8: Fold Nested Subagent Trees Into Interrupt, Archive, Delete, And Purge

**Files:**
- Modify: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Modify: `core_matrix/app/services/conversations/request_resource_closes.rb`
- Modify: `core_matrix/app/services/conversations/progress_close_requests.rb`
- Modify: `core_matrix/app/services/conversations/archive.rb`
- Modify: `core_matrix/app/services/conversations/finalize_deletion.rb`
- Modify: `core_matrix/app/services/conversations/purge_plan.rb`
- Modify: `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- Modify: `core_matrix/test/services/conversations/archive_test.rb`
- Modify: `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- Modify: `core_matrix/test/services/conversations/purge_deleted_test.rb`

**Step 1: Write the failing tests**

Cover:

- turn interrupt closes turn-scoped threads created by that turn
- turn interrupt stops in-flight child work requested by the owner turn
- archive without force blocks on open threads
- archive force blocks new spawn and send requests
- delete and purge fail closed until nested subagent residue is gone
- purge removes owned child conversations and mailbox residue depth-first

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/conversations/archive_test.rb \
  test/services/conversations/purge_deleted_test.rb
```

Expected: FAIL because lifecycle code still assumes either `SubagentRun` or
non-nested ownership.

**Step 3: Write the minimal implementation**

- switch archive and blocker queries to `SubagentThread`
- recurse owned thread trees for force-close and purge
- ensure conversation-scoped threads survive interrupted work but not owner
  deletion
- keep fork and branch lineage semantics unchanged

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/request_turn_interrupt.rb \
  core_matrix/app/services/conversations/request_resource_closes.rb \
  core_matrix/app/services/conversations/progress_close_requests.rb \
  core_matrix/app/services/conversations/archive.rb \
  core_matrix/app/services/conversations/finalize_deletion.rb \
  core_matrix/app/services/conversations/purge_plan.rb \
  core_matrix/app/queries/conversations/blocker_snapshot_query.rb \
  core_matrix/test/services/conversations/request_turn_interrupt_test.rb \
  core_matrix/test/services/conversations/archive_test.rb \
  core_matrix/test/services/conversations/purge_deleted_test.rb
git commit -m "refactor: fold nested subagent threads into conversation lifecycle"
```

## Task 9: Rewrite Behavior Docs And Remove Stale Terminology

**Files:**
- Modify: `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- Modify: `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- Modify: `agents/fenix/README.md`

**Step 1: Update the docs after the code lands**

Make sure the docs now state:

- `SubagentThread` is the durable control aggregate
- nested subagents are in scope
- `profile_catalog` belongs to the runtime manifest and capability snapshot
- root interactive profile is fixed to `main`
- `agent_context` is part of the frozen execution snapshot
- conversation-visible tools are filtered per conversation
- Fenix owns prompt building and internal model-slot switching

**Step 2: Run the stale-term grep**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "SubagentRun|subagent run" core_matrix agents/fenix docs
```

Expected: no stale matches except where historical context is explicitly
describing the removed model.

**Step 3: Commit**

```bash
git add core_matrix/docs/behavior/subagent-runs-and-execution-leases.md \
  core_matrix/docs/behavior/agent-registration-and-capability-handshake.md \
  core_matrix/docs/behavior/agent-runtime-resource-apis.md \
  core_matrix/docs/behavior/conversation-structure-and-lineage.md \
  core_matrix/docs/behavior/turn-entry-and-selector-state.md \
  core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md \
  core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  core_matrix/docs/behavior/human-interactions-and-conversation-events.md \
  agents/fenix/README.md
git commit -m "docs: align behavior docs with profile-aware subagent threads"
```

## Final Verification

Run the full verification suites for both affected projects.

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
rg -n "do not add nested subagent|does not add nested subagent|out of scope.*nested" docs core_matrix agents/fenix
rg -n "profile_catalog|interactive\\.profile|subagents\\.|agent_context" core_matrix agents/fenix docs
```

Expected:

- no stale `SubagentRun` implementation references remain
- no stale design text says nested subagents are out of scope
- the new profile-aware contract appears in code, tests, and docs

## Completion Checklist

- `SubagentRun` is fully removed
- `SubagentThread` is the only durable subagent control aggregate
- profile metadata is runtime-declared and frozen into execution
- root interactive profile remains fixed to `main`
- nested subagent policy is enforced through conversation-visible tool
  filtering
- Fenix reuses one loop for root and subagent execution
- archive, delete, and purge handle nested subagent trees without residue
- behavior docs, plan docs, and tests use consistent terminology
