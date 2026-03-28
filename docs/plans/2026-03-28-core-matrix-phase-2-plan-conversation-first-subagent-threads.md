# Conversation-First Subagent Threads Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace workflow-owned `SubagentRun` coordination with conversation-first `SubagentThread` control, reserved platform-level subagent tools, and owner-conversation lifecycle handling that archives, deletes, and purges without leaking runtime residue.

**Architecture:** Reuse the existing Core Matrix primitives instead of inventing a parallel stack. `Conversation` remains the transcript and lineage aggregate, `SubagentThread` becomes the durable control row, `AgentTaskRun(kind = "subagent_step")` stays the execution instance, and mailbox close control plus `ConversationEvent` projection are extended to the new thread model. The batch is intentionally breaking: remove `SubagentRun`, rewrite the old migrations, regenerate `schema.rb`, and update every behavior doc and test to the new terminology.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record, Action Cable control plane, Minitest, behavior docs in `core_matrix/docs/behavior`, plan docs in `docs/plans`

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
  - `ConversationEvent`
  - `ConversationCloseOperation`
  - `AgentControlMailboxItem`
  - `RuntimeCapabilities::ComposeEffectiveToolCatalog`
- After every major task, run `rg -n "SubagentRun"` and `rg -n "subagent_spawn"`
  to confirm no stale semantics remain in the touched slice.
- Keep all external and agent-facing references on `public_id`.
- Do not add nested subagent spawning or fork inheritance in this batch.

## Mandatory Scenario Gate

Before shipping, all of these scenario families must have explicit tests:

- schema and model contracts
- reserved capability injection
- spawn, send, list, wait, and close flows
- conversation addressability guard
- turn interrupt behavior for both `scope = turn` and
  `scope = conversation`
- archive, delete, finalize, and purge behavior
- fork non-inheritance
- grep-based removal of `SubagentRun` from code, docs, tests, and schema

## Known File Targets

Start from this list and keep it current while implementing.

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
- Modify: `core_matrix/app/models/workflow_artifact.rb`
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
- Modify: `core_matrix/test/models/agent_task_run_test.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/models/execution_lease_test.rb`
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
- Modify: `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- Delete: `core_matrix/app/models/subagent_run.rb`
- Delete: `core_matrix/app/services/subagents/spawn.rb`
- Delete: `core_matrix/test/models/subagent_run_test.rb`
- Delete: `core_matrix/test/services/subagents/spawn_test.rb`

### Task 1: Rewrite The Schema Around `SubagentThread`

**Files:**
- Create: `core_matrix/app/models/subagent_thread.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/models/execution_lease.rb`
- Modify: `core_matrix/app/models/workflow_artifact.rb`
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
- `SubagentThread` close metadata rules through `ClosableRuntimeResource`
- `AgentTaskRun` support for `subagent_thread_id` and `requested_by_turn_id`
- `ExecutionLease` allowlist swapping `SubagentRun` for `SubagentThread`

Example expectation:

```ruby
test "scope turn requires origin turn" do
  thread = SubagentThread.new(scope: "turn", owner_conversation: owner, conversation: child)

  assert_not thread.valid?
  assert_includes thread.errors[:origin_turn], "must exist"
end
```

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
  core_matrix/app/models/workflow_artifact.rb \
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

### Task 2: Inject Reserved Subagent Tools Through The Existing Capability Composer

**Files:**
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/models/runtime_capability_contract.rb`
- Modify: `core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`
- Modify: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Modify: `core_matrix/test/requests/agent_api/capabilities_test.rb`
- Modify: `core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `core_matrix/test/models/capability_snapshot_test.rb`

**Step 1: Write the failing tests**

Add coverage for:

- reserved tool injection into `effective_tool_catalog`
- stable ordering and name normalization
- rejection of runtime attempts to redefine reserved tool names

Example expectation:

```ruby
assert_equal %w[subagent_close subagent_list subagent_send subagent_spawn subagent_wait],
  contract.effective_tool_catalog
    .select { |entry| entry.fetch("tool_name").start_with?("subagent_") }
    .map { |entry| entry.fetch("tool_name") }
    .sort
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb \
  test/services/agent_deployments/handshake_test.rb \
  test/requests/agent_api/capabilities_test.rb \
  test/integration/agent_registration_contract_test.rb \
  test/models/capability_snapshot_test.rb
```

Expected: FAIL because only `subagent_spawn` exists today and it is not a
reserved Core Matrix tool.

**Step 3: Write the minimal implementation**

- define the reserved Core Matrix subagent tool entries in
  `CORE_MATRIX_TOOL_CATALOG`
- keep runtime snapshots intact while making the effective catalog include the
  reserved entries
- reject duplicate runtime definitions for those names

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Grep for stale capability assumptions**

Run:

```bash
cd core_matrix
rg -n "\"subagent_spawn\"|default_tool_catalog\\(" test app
```

Expected: remaining matches now refer to the reserved built-in family, not the
old single-tool assumption.

**Step 6: Commit**

```bash
git add core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb \
  core_matrix/app/models/runtime_capability_contract.rb \
  core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb \
  core_matrix/test/services/agent_deployments/handshake_test.rb \
  core_matrix/test/requests/agent_api/capabilities_test.rb \
  core_matrix/test/integration/agent_registration_contract_test.rb \
  core_matrix/test/models/capability_snapshot_test.rb
git commit -m "refactor: reserve platform subagent tools"
```

### Task 3: Add The Subagent Conversation Guard And Message Services

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
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write the failing tests**

Cover:

- human callers cannot append turns or transcript to an
  `agent_addressable` conversation
- only `owner_agent`, `subagent_self`, and `system` senders are accepted
- successful sends append transcript and project an audit event

Example expectation:

```ruby
test "send_message projects an audit event" do
  message = SubagentThreads::SendMessage.call(
    subagent_thread: thread,
    sender_kind: "owner_agent",
    content: "Investigate the failure"
  )

  event = ConversationEvent.where(conversation: thread.conversation).order(:projection_sequence).last
  assert_equal "subagent_thread.message_delivered", event.event_kind
  assert_equal message.public_id, event.payload.fetch("message_public_id")
end
```

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
- keep transcript-bearing content on normal `Message` rows; do not add sender
  columns to `messages`

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
  core_matrix/test/services/turns/queue_follow_up_test.rb \
  core_matrix/test/test_helper.rb
git commit -m "feat: guard subagent conversation writes"
```

### Task 4: Implement `subagent_spawn` And `subagent_list` On Top Of Child Conversations

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
- initial child work is scheduled through `AgentTaskRun(kind = "subagent_step")`
- list only returns threads owned by the current conversation

Example expectation:

```ruby
assert_equal "agent_addressable", spawned.conversation.addressability
assert_equal "subagent_step", spawned.current_task_run.task_kind
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/subagent_threads/spawn_test.rb \
  test/services/turns/start_agent_turn_test.rb \
  test/services/workflows/create_for_turn_test.rb
```

Expected: FAIL because the new spawn path and list path are not wired.

**Step 3: Write the minimal implementation**

- create the child conversation
- reuse `Conversations::CreateThread` for lineage and canonical-store setup
- create the `SubagentThread`
- append the initial delegated message
- allocate child turn/workflow/task work through `Turns::StartAgentTurn`,
  `Workflows::CreateForTurn`, and `AgentControl::CreateExecutionAssignment`
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
git commit -m "feat: spawn subagent threads as child conversations"
```

### Task 5: Implement `subagent_wait` And `subagent_close` Using Existing Close Control

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

Example expectation:

```ruby
assert_equal "closed", thread.reload.close_state
assert_equal "closed", thread.reload.lifecycle_state
```

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
- route close requests to the child runtime using the existing mailbox item
  contract
- update close outcomes to mutate `SubagentThread`
- implement `SubagentThreads::Wait` without a generic sleep primitive

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
git commit -m "feat: add wait and close control for subagent threads"
```

### Task 6: Rewire Turn Interrupt And Blocker Queries

**Files:**
- Modify: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Modify: `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- Modify: `core_matrix/app/services/conversations/request_resource_closes.rb`
- Modify: `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- Modify: `core_matrix/test/services/conversations/reconcile_close_operation_test.rb`

**Step 1: Write the failing tests**

Cover:

- turn-scoped thread closes when the owner turn is interrupted
- conversation-scoped thread keeps `lifecycle_state = open` while the active
  child `subagent_step` requested by the interrupted owner turn is terminated
- blocker snapshots count owned open threads correctly

Example expectation:

```ruby
assert_equal "open", conversation_scoped_thread.reload.lifecycle_state
assert_equal "interrupted", conversation_scoped_thread.reload.last_known_status
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/conversations/reconcile_close_operation_test.rb
```

Expected: FAIL because turn interrupt still only knows about workflow-owned
`SubagentRun`.

**Step 3: Write the minimal implementation**

- find turn-scoped threads by `origin_turn_id`
- find in-flight child `subagent_step` work by `requested_by_turn_id`
- close or interrupt the correct resources without closing reusable
  conversation-scoped threads
- update blocker counting from running `SubagentRun` to owned open
  `SubagentThread`

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/request_turn_interrupt.rb \
  core_matrix/app/queries/conversations/blocker_snapshot_query.rb \
  core_matrix/app/services/conversations/request_resource_closes.rb \
  core_matrix/test/services/conversations/request_turn_interrupt_test.rb \
  core_matrix/test/services/conversations/reconcile_close_operation_test.rb
git commit -m "refactor: align turn interrupt with subagent threads"
```

### Task 7: Rewire Archive, Delete, Progress-Close, And Purge

**Files:**
- Modify: `core_matrix/app/services/conversations/archive.rb`
- Modify: `core_matrix/app/services/conversations/finalize_deletion.rb`
- Modify: `core_matrix/app/services/conversations/progress_close_requests.rb`
- Modify: `core_matrix/app/services/conversations/purge_plan.rb`
- Modify: `core_matrix/test/services/conversations/archive_test.rb`
- Modify: `core_matrix/test/services/conversations/purge_deleted_test.rb`
- Modify: `core_matrix/test/services/conversations/finalize_deletion_test.rb`

**Step 1: Write the failing tests**

Cover:

- archive without force blocks on open subagent threads
- archive force requests subagent thread close and prevents new spawn or send
- finalize deletion refuses to proceed with open or close-pending threads
- purge tears down owned child subagent conversations and leaves no residue

Example expectation:

```ruby
assert_difference("SubagentThread.count", -1) do
  Conversations::PurgePlan.new(conversation: deleted_conversation).execute!
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/archive_test.rb \
  test/services/conversations/finalize_deletion_test.rb \
  test/services/conversations/purge_deleted_test.rb
```

Expected: FAIL because archive, finalize, progress-close, and purge still
expect workflow-owned `SubagentRun` residue.

**Step 3: Write the minimal implementation**

- switch archive blockers to `SubagentThread`
- ensure close progression uses owner conversation semantics
- teach progress-close and purge-plan to traverse owned subagent thread and
  child conversation residue
- fail closed if active thread residue remains

**Step 4: Run tests to verify they pass**

Run the same command from Step 2 and confirm PASS.

**Step 5: Grep for stale lifecycle references**

Run:

```bash
cd core_matrix
rg -n "SubagentRun|subagent_runs" app/services/conversations test/services/conversations
```

Expected: no remaining matches.

**Step 6: Commit**

```bash
git add core_matrix/app/services/conversations/archive.rb \
  core_matrix/app/services/conversations/finalize_deletion.rb \
  core_matrix/app/services/conversations/progress_close_requests.rb \
  core_matrix/app/services/conversations/purge_plan.rb \
  core_matrix/test/services/conversations/archive_test.rb \
  core_matrix/test/services/conversations/finalize_deletion_test.rb \
  core_matrix/test/services/conversations/purge_deleted_test.rb
git commit -m "refactor: fold subagent threads into conversation lifecycle"
```

### Task 8: Rewrite Behavior Docs And Delete Obsolete Terminology

**Files:**
- Modify: `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`

**Step 1: Write the failing review checklist**

Before editing, create a temporary checklist in the commit message draft or
scratch notes that every document must answer:

- what owns a subagent now
- where subagent transcript lives
- which tool surface is reserved
- how archive/delete/purge treat subagent threads
- how human access is blocked
- which old `SubagentRun` terminology must disappear

**Step 2: Rewrite the docs**

Update the docs so they consistently say:

- subagents are conversation-first
- `SubagentThread` is the control aggregate
- `AgentTaskRun(kind = "subagent_step")` is the execution instance
- `ConversationEvent` is the operational projection surface
- fork does not inherit subagent threads

**Step 3: Run grep-based doc verification**

Run:

```bash
cd core_matrix
rg -n "SubagentRun|subagent_runs|workflow-owned runtime resource for nested agent work" docs/behavior docs/plans
```

Expected: the only remaining mentions are historical plan references that are
not part of the active behavior contract, or no matches if those plans are
also updated.

**Step 4: Commit**

```bash
git add core_matrix/docs/behavior/subagent-runs-and-execution-leases.md \
  core_matrix/docs/behavior/agent-runtime-resource-apis.md \
  core_matrix/docs/behavior/conversation-structure-and-lineage.md \
  core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  core_matrix/docs/behavior/human-interactions-and-conversation-events.md
git commit -m "docs: rewrite subagent behavior contracts"
```

### Task 9: Exhaustive Cleanup, Broad Verification, And Final Audit

**Files:**
- Modify: every touched file from Tasks 1 through 8 as needed

**Step 1: Run exhaustive stale-reference checks**

Run:

```bash
cd core_matrix
rg -n "SubagentRun|subagent_runs" app test docs db
rg -n "Subagents::Spawn|app/services/subagents/spawn" app test docs
rg -n "\"subagent_spawn\"" app test docs
```

Expected:

- no `SubagentRun` or `subagent_runs` matches remain
- no old `Subagents::Spawn` matches remain
- `subagent_spawn` appears only as one member of the reserved tool family

**Step 2: Run the focused test batches again**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/subagent_thread_test.rb \
  test/services/subagent_threads \
  test/services/conversations/archive_test.rb \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/services/agent_control/report_test.rb \
  test/requests/agent_api/capabilities_test.rb \
  test/integration/agent_registration_contract_test.rb
```

Expected: PASS.

**Step 3: Run the project verification bundle**

Run:

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected: PASS. If any unrelated failures appear, document them with exact
output before deciding whether they are pre-existing or caused by this batch.

**Step 4: Perform the final architecture audit**

Confirm in writing before closing the task:

- the new design is orthogonal with the rest of Core Matrix
- no duplicate control plane or event plane was introduced
- existing close-control and capability-composer infrastructure were reused
- the implementation does not leak open subagent residue through archive,
  delete, or purge
- no user-facing or agent-facing boundary exposes internal ids

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: land conversation-first subagent threads"
```

## Completion Checklist

- all scenarios from the design doc have direct tests
- `SubagentRun` is gone
- `SubagentThread` is the only durable subagent control row
- child subagent conversations are `agent_addressable`
- reserved subagent tools are platform-owned
- archive, delete, finalize, and purge all handle owned subagent residue
- docs, code, tests, and schema use the same terminology
