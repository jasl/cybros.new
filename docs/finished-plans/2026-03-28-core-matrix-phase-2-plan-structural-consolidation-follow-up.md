# Core Matrix Phase 2 Structural Consolidation Follow-Up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate the highest-risk structural hotspots from the architecture-health audit by splitting provider turn execution and deployment recovery into smaller contracts, unifying lifecycle and mutation blocker enforcement, and introducing explicit builders for the highest-value runtime payloads they depend on.

**Architecture:** Start by centralizing provider request-setting schema and the contract objects that shape provider request context, workflow wait state, conversation blocker state, and runtime capability state. Then split the two orchestration hotspots so `ProviderExecution::ExecuteTurnStep`, `AgentDeployments::MarkUnavailable`, and `AgentDeployments::AutoResumeWorkflows` stay as public entrypoints but delegate planning, transport, and persistence to narrower collaborators. Finish by collapsing close summaries and mutation guards onto one blocker snapshot so enforcement paths and operator-facing summaries read from the same model instead of re-encoding the same rules in parallel.

**Tech Stack:** Ruby on Rails (`core_matrix`), plain Ruby value objects under `app/models`, Active Record transactions and row locks, Minitest model/service/query/request tests, existing Phase 2 behavior docs, `rg`, `bin/rails test`, `bin/rubocop`

---

## Execution Rules

- Treat this as one structural consolidation batch, not as a bugfix grab bag.
- Keep the current public orchestrator entrypoints stable:
  - `ProviderExecution::ExecuteTurnStep`
  - `AgentDeployments::MarkUnavailable`
  - `AgentDeployments::AutoResumeWorkflows`
  - `Conversations::ValidateMutableState`
  - `Turns::ValidateTimelineMutationTarget`
  - `RuntimeCapabilities::ComposeForConversation`
  - `AgentAPI::CapabilitiesController`
- Do not leave compatibility constants or duplicate schema tables behind after a
  task finishes. The old path should be deleted or reduced to one thin adapter.
- Every new contract object introduced in this batch must expose narrow readers
  plus `to_h`, and callers should stop reaching into raw hashes when a named
  reader exists.
- Do not expose internal numeric ids at any agent-facing or external boundary;
  preserve the existing `public_id` policy.
- Keep provider-governance validation, provider transport, workflow recovery,
  and conversation lifecycle enforcement orthogonal even when they now share
  contract objects.
- Update behavior docs before final verification so the final pass reads like a
  coherent system, not just a set of passing tests.
- Commit after every task with the suggested message or a tighter equivalent.

## Explicitly Out Of Scope

- Broad read-side naming cleanup across every `Query` class
- New provider wire APIs or multimodal product features
- Full JSON-contract cleanup outside the touched provider, recovery, blocker,
  and runtime-capability families
- Any new user-facing behavior beyond tighter consistency across existing flows

## Final Deliverables

This plan must finish with the following new or materially refactored contract
surfaces in place:

- `core_matrix/app/models/provider_request_settings_schema.rb`
- `core_matrix/app/models/provider_request_context.rb`
- `core_matrix/app/models/workflow_wait_snapshot.rb`
- `core_matrix/app/models/agent_deployment_recovery_plan.rb`
- `core_matrix/app/models/conversation_blocker_snapshot.rb`
- `core_matrix/app/models/runtime_capability_contract.rb`
- A thinner `ProviderExecution::ExecuteTurnStep`
- A thinner deployment outage and auto-resume control flow
- One blocker snapshot reused by close summary and mutation enforcement

### Task 1: Centralize Provider Request Settings And Request Context Contracts

**Files:**
- Create: `core_matrix/app/models/provider_request_settings_schema.rb`
- Create: `core_matrix/app/models/provider_request_context.rb`
- Modify: `core_matrix/app/services/provider_catalog/validate.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/app/services/provider_execution/build_request_context.rb`
- Test: `core_matrix/test/models/provider_request_settings_schema_test.rb`
- Test: `core_matrix/test/models/provider_request_context_test.rb`
- Test: `core_matrix/test/services/provider_catalog/validate_test.rb`
- Test: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Test: `core_matrix/test/services/provider_execution/build_request_context_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- `ProviderRequestSettingsSchema` is the only place that knows which
  request-setting keys are legal for each wire API
- provider catalog validation rejects unsupported defaults by asking the schema
- execution snapshot assembly filters user config and model defaults through the
  same schema object
- request-context building returns a named contract object with stable readers
  and `to_h`

Example expectation:

```ruby
test "build execution snapshot uses the shared provider request-setting schema" do
  turn = create_turn_with_resolved_provider!(
    wire_api: "chat_completions",
    request_defaults: { "temperature" => 0.7, "top_p" => 0.8 },
    resolved_config_snapshot: { "temperature" => 0.4, "sandbox" => "workspace-write" }
  )

  snapshot = Workflows::BuildExecutionSnapshot.call(turn: turn)

  assert_equal(
    { "temperature" => 0.4, "top_p" => 0.8 },
    snapshot.provider_execution.fetch("execution_settings")
  )
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/provider_request_settings_schema_test.rb \
  test/models/provider_request_context_test.rb \
  test/services/provider_catalog/validate_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/provider_execution/build_request_context_test.rb
```

Expected: FAIL because the schema and request-context contract classes do not
exist yet and request-setting rules still live in multiple places.

**Step 3: Write the minimal implementation**

Implement:

- `ProviderRequestSettingsSchema`
  - one canonical table for allowed keys and validators per wire API
  - methods to validate request defaults and to filter merged execution
    settings
- `ProviderRequestContext`
  - named readers for provider handle, model ref, api model, wire API,
    transport, tokenizer hint, execution settings, hard limits, advisory hints,
    and metadata
  - `to_h` that round-trips the persisted request context contract
- `ProviderCatalog::Validate`
  - use `ProviderRequestSettingsSchema` instead of its own local constant
- `Workflows::BuildExecutionSnapshot`
  - build `provider_execution["execution_settings"]` through the schema object
- `ProviderExecution::BuildRequestContext`
  - build and validate `ProviderRequestContext`, then return its `to_h` so the
    public behavior stays stable for the next task

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/provider_request_settings_schema.rb \
  core_matrix/app/models/provider_request_context.rb \
  core_matrix/app/services/provider_catalog/validate.rb \
  core_matrix/app/services/workflows/build_execution_snapshot.rb \
  core_matrix/app/services/provider_execution/build_request_context.rb \
  core_matrix/test/models/provider_request_settings_schema_test.rb \
  core_matrix/test/models/provider_request_context_test.rb \
  core_matrix/test/services/provider_catalog/validate_test.rb \
  core_matrix/test/services/workflows/build_execution_snapshot_test.rb \
  core_matrix/test/services/provider_execution/build_request_context_test.rb
git commit -m "refactor: centralize provider request contracts"
```

### Task 2: Split Provider Turn Execution Into Narrow Collaborators

**Files:**
- Create: `core_matrix/app/services/provider_execution/dispatch_request.rb`
- Create: `core_matrix/app/services/provider_execution/with_fresh_execution_state_lock.rb`
- Create: `core_matrix/app/services/provider_execution/persist_turn_step_success.rb`
- Create: `core_matrix/app/services/provider_execution/persist_turn_step_failure.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Test: `core_matrix/test/services/provider_execution/dispatch_request_test.rb`
- Test: `core_matrix/test/services/provider_execution/persist_turn_step_success_test.rb`
- Test: `core_matrix/test/services/provider_execution/persist_turn_step_failure_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- request dispatch can be exercised without also mutating turns and workflow
  rows
- success persistence can be exercised with a fake provider result and no HTTP
  adapter
- failure persistence can be exercised with a fake provider error and no
  transcript setup unrelated to the failure path
- `ExecuteTurnStep` remains the public entrypoint and still drives the same
  end-to-end behavior

Example expectation:

```ruby
test "persist turn step success owns terminal writes and node completion events" do
  context = build_provider_execution_context!
  provider_result = ProviderExecution::DispatchRequest::Result.new(
    provider_request_id: "req-1",
    content: "Hello",
    usage: { "input_tokens" => 5, "output_tokens" => 7 },
    raw_response_metadata: {}
  )

  result = ProviderExecution::PersistTurnStepSuccess.call(
    workflow_node: context[:workflow_node],
    request_context: context[:request_context],
    provider_result: provider_result,
    duration_ms: 123
  )

  assert_equal "completed", result.workflow_run.reload.lifecycle_state
  assert_equal "completed", result.workflow_node.reload.events.last.status
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/provider_execution/dispatch_request_test.rb \
  test/services/provider_execution/persist_turn_step_success_test.rb \
  test/services/provider_execution/persist_turn_step_failure_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

Expected: FAIL because the new collaborators do not exist and the current
service still owns the whole flow directly.

**Step 3: Write the minimal implementation**

Implement:

- `DispatchRequest`
  - own client construction, transport invocation, provider request id
    extraction, usage normalization, and duration capture
- `WithFreshExecutionStateLock`
  - own turn/workflow/node lock order, reloads, and stale-result fencing
- `PersistTurnStepSuccess`
  - own output variant creation, usage event creation, profiling fact
    recording, terminal turn and workflow updates, and final node event
- `PersistTurnStepFailure`
  - own failure profiling, failed lifecycle updates, and failed node event
- `ExecuteTurnStep`
  - reduce to validation, request-context assembly, dispatch, and routing to
    the success or failure persistor

Do not let success and failure paths each keep their own copy of freshness
locking or terminal-event checks.

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/dispatch_request.rb \
  core_matrix/app/services/provider_execution/with_fresh_execution_state_lock.rb \
  core_matrix/app/services/provider_execution/persist_turn_step_success.rb \
  core_matrix/app/services/provider_execution/persist_turn_step_failure.rb \
  core_matrix/app/services/provider_execution/execute_turn_step.rb \
  core_matrix/test/services/provider_execution/dispatch_request_test.rb \
  core_matrix/test/services/provider_execution/persist_turn_step_success_test.rb \
  core_matrix/test/services/provider_execution/persist_turn_step_failure_test.rb \
  core_matrix/test/services/provider_execution/execute_turn_step_test.rb
git commit -m "refactor: split provider turn execution flow"
```

### Task 3: Introduce Workflow Wait Snapshots And Deployment Recovery Plans

**Files:**
- Create: `core_matrix/app/models/workflow_wait_snapshot.rb`
- Create: `core_matrix/app/models/agent_deployment_recovery_plan.rb`
- Create: `core_matrix/app/services/agent_deployments/build_recovery_plan.rb`
- Create: `core_matrix/app/services/agent_deployments/apply_recovery_plan.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/services/agent_deployments/unavailable_pause_state.rb`
- Modify: `core_matrix/app/services/agent_deployments/mark_unavailable.rb`
- Modify: `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
- Test: `core_matrix/test/models/workflow_wait_snapshot_test.rb`
- Test: `core_matrix/test/models/agent_deployment_recovery_plan_test.rb`
- Test: `core_matrix/test/services/agent_deployments/build_recovery_plan_test.rb`
- Test: `core_matrix/test/services/agent_deployments/apply_recovery_plan_test.rb`
- Test: `core_matrix/test/services/agent_deployments/mark_unavailable_test.rb`
- Test: `core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- wait snapshots round-trip both `agent_unavailable` pauses and restored
  pre-outage blockers like `human_interaction`
- recovery planning returns one explicit action:
  - `resume`
  - `resume_with_rebind`
  - `manual_recovery_required`
- drift classification and pause-snapshot semantics are tested separately from
  top-level auto-resume iteration
- `MarkUnavailable` and `AutoResumeWorkflows` still keep their existing public
  behavior after delegating to the planner and applier

Example expectation:

```ruby
test "build recovery plan marks capability drift for manual recovery" do
  context = build_waiting_recovery_context_with_capability_drift!

  plan = AgentDeployments::BuildRecoveryPlan.call(
    deployment: context[:replacement],
    workflow_run: context[:workflow_run]
  )

  assert_equal "manual_recovery_required", plan.action
  assert_equal "capability_snapshot_version_drift", plan.drift_reason
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/workflow_wait_snapshot_test.rb \
  test/models/agent_deployment_recovery_plan_test.rb \
  test/services/agent_deployments/build_recovery_plan_test.rb \
  test/services/agent_deployments/apply_recovery_plan_test.rb \
  test/services/agent_deployments/mark_unavailable_test.rb \
  test/services/agent_deployments/auto_resume_workflows_test.rb
```

Expected: FAIL because wait snapshots and recovery plans are still implicit
hashes and the planner/applier collaborators do not exist yet.

**Step 3: Write the minimal implementation**

Implement:

- `WorkflowWaitSnapshot`
  - parse the persisted wait snapshot payload
  - expose helpers for resume attributes and blocker-resolution checks
- `AgentDeploymentRecoveryPlan`
  - named readers for action, drift reason, whether turn rebinding is needed,
    and any rewritten selector or execution snapshot inputs
- `BuildRecoveryPlan`
  - own runtime-identity comparison, rotated replacement checks, selector
    re-resolution, drift classification, and resume-versus-escalate choice
- `ApplyRecoveryPlan`
  - own state mutation for ready restore, snapshot restore, manual recovery
    escalation, audit logging, and turn rebinding
- `UnavailablePauseState`
  - reduce to a thin adapter around `WorkflowWaitSnapshot`
- `MarkUnavailable` and `AutoResumeWorkflows`
  - keep iteration and transaction boundaries, but delegate pause and resume
    semantics to the new contract objects
- `WorkflowRun`
  - add a helper reader for the parsed wait snapshot if that makes callers
    smaller and clearer

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/workflow_wait_snapshot.rb \
  core_matrix/app/models/agent_deployment_recovery_plan.rb \
  core_matrix/app/services/agent_deployments/build_recovery_plan.rb \
  core_matrix/app/services/agent_deployments/apply_recovery_plan.rb \
  core_matrix/app/models/workflow_run.rb \
  core_matrix/app/services/agent_deployments/unavailable_pause_state.rb \
  core_matrix/app/services/agent_deployments/mark_unavailable.rb \
  core_matrix/app/services/agent_deployments/auto_resume_workflows.rb \
  core_matrix/test/models/workflow_wait_snapshot_test.rb \
  core_matrix/test/models/agent_deployment_recovery_plan_test.rb \
  core_matrix/test/services/agent_deployments/build_recovery_plan_test.rb \
  core_matrix/test/services/agent_deployments/apply_recovery_plan_test.rb \
  core_matrix/test/services/agent_deployments/mark_unavailable_test.rb \
  core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb
git commit -m "refactor: plan deployment recovery explicitly"
```

### Task 4: Centralize Conversation Blocker Snapshots And Close Summary Projections

**Files:**
- Create: `core_matrix/app/models/conversation_blocker_snapshot.rb`
- Create: `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- Modify: `core_matrix/app/queries/conversations/dependency_blockers_query.rb`
- Modify: `core_matrix/app/queries/conversations/work_barrier_query.rb`
- Modify: `core_matrix/app/queries/conversations/close_summary_query.rb`
- Modify: `core_matrix/app/services/conversations/reconcile_close_operation.rb`
- Test: `core_matrix/test/models/conversation_blocker_snapshot_test.rb`
- Test: `core_matrix/test/queries/conversations/blocker_snapshot_query_test.rb`
- Test: `core_matrix/test/queries/conversations/dependency_blockers_query_test.rb`
- Test: `core_matrix/test/queries/conversations/work_barrier_query_test.rb`
- Test: `core_matrix/test/queries/conversations/close_summary_query_test.rb`
- Test: `core_matrix/test/services/conversations/reconcile_close_operation_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- one blocker snapshot can answer:
  - mainline clear?
  - tail pending?
  - tail degraded?
  - dependency blocked?
  - mutable for live mutation?
- `CloseSummaryQuery` is now just a projection of the same blocker snapshot
- `ReconcileCloseOperation` stops hand-encoding close-state decisions from raw
  hashes and asks the blocker snapshot for the derived predicates

Example expectation:

```ruby
test "close summary reuses the canonical blocker snapshot" do
  conversation = create_conversation_with_open_blockers!

  snapshot = Conversations::BlockerSnapshotQuery.call(conversation: conversation)
  summary = Conversations::CloseSummaryQuery.call(conversation: conversation)

  assert_equal snapshot.to_h, summary
  assert_equal true, snapshot.dependency_blocked?
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/conversation_blocker_snapshot_test.rb \
  test/queries/conversations/blocker_snapshot_query_test.rb \
  test/queries/conversations/dependency_blockers_query_test.rb \
  test/queries/conversations/work_barrier_query_test.rb \
  test/queries/conversations/close_summary_query_test.rb \
  test/services/conversations/reconcile_close_operation_test.rb
```

Expected: FAIL because the blocker snapshot query and contract do not exist yet
and close summary is still assembled independently.

**Step 3: Write the minimal implementation**

Implement:

- `ConversationBlockerSnapshot`
  - preserve the current mainline, tail, and dependency fields
  - add predicate helpers used by close reconciliation and guard enforcement
- `Conversations::BlockerSnapshotQuery`
  - build one canonical snapshot from current conversation state
- `DependencyBlockersQuery`
  - keep the focused dependency query if it still helps composition, but have
    it feed the blocker snapshot instead of parallel close logic
- `WorkBarrierQuery`
  - either delegate to the blocker snapshot or become a thin compatibility
    projection; do not keep a second independent counter family
- `CloseSummaryQuery`
  - return the blocker snapshot `to_h`
- `ReconcileCloseOperation`
  - use blocker snapshot predicates rather than re-decoding summary hashes by
    hand

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/conversation_blocker_snapshot.rb \
  core_matrix/app/queries/conversations/blocker_snapshot_query.rb \
  core_matrix/app/queries/conversations/dependency_blockers_query.rb \
  core_matrix/app/queries/conversations/work_barrier_query.rb \
  core_matrix/app/queries/conversations/close_summary_query.rb \
  core_matrix/app/services/conversations/reconcile_close_operation.rb \
  core_matrix/test/models/conversation_blocker_snapshot_test.rb \
  core_matrix/test/queries/conversations/blocker_snapshot_query_test.rb \
  core_matrix/test/queries/conversations/dependency_blockers_query_test.rb \
  core_matrix/test/queries/conversations/work_barrier_query_test.rb \
  core_matrix/test/queries/conversations/close_summary_query_test.rb \
  core_matrix/test/services/conversations/reconcile_close_operation_test.rb
git commit -m "refactor: centralize conversation blocker snapshots"
```

### Task 5: Collapse Mutation And Timeline Guards Onto The Blocker Snapshot

**Files:**
- Modify: `core_matrix/app/services/conversations/validate_mutable_state.rb`
- Modify: `core_matrix/app/services/conversations/with_mutable_state_lock.rb`
- Modify: `core_matrix/app/services/workflows/with_mutable_workflow_context.rb`
- Modify: `core_matrix/app/services/turns/validate_timeline_mutation_target.rb`
- Modify: `core_matrix/app/services/turns/with_timeline_mutation_lock.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `core_matrix/app/services/workflows/manual_retry.rb`
- Modify: `core_matrix/app/services/workflows/step_retry.rb`
- Modify: `core_matrix/app/services/canonical_stores/write_support.rb`
- Modify: `core_matrix/app/services/variables/promote_to_workspace.rb`
- Modify: `core_matrix/app/services/human_interactions/request.rb`
- Modify: `core_matrix/app/services/human_interactions/resolve_approval.rb`
- Modify: `core_matrix/app/services/human_interactions/submit_form.rb`
- Modify: `core_matrix/app/services/human_interactions/complete_task.rb`
- Modify: `core_matrix/app/services/conversations/create_branch.rb`
- Modify: `core_matrix/app/services/conversations/create_thread.rb`
- Modify: `core_matrix/app/services/conversations/create_checkpoint.rb`
- Modify: `core_matrix/app/services/conversations/add_import.rb`
- Modify: `core_matrix/app/services/conversations/update_override.rb`
- Modify: `core_matrix/app/services/conversation_summaries/create_segment.rb`
- Modify: `core_matrix/app/services/messages/update_visibility.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Modify: `core_matrix/app/services/turns/edit_tail_input.rb`
- Modify: `core_matrix/app/services/turns/select_output_variant.rb`
- Modify: `core_matrix/app/services/turns/retry_output.rb`
- Modify: `core_matrix/app/services/turns/rerun_output.rb`
- Modify: `core_matrix/app/services/conversations/rollback_to_turn.rb`
- Test: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Test: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Test: `core_matrix/test/services/turns/start_automation_turn_test.rb`
- Test: `core_matrix/test/services/workflows/manual_resume_test.rb`
- Test: `core_matrix/test/services/workflows/manual_retry_test.rb`
- Test: `core_matrix/test/services/workflows/step_retry_test.rb`
- Test: `core_matrix/test/services/canonical_stores/set_test.rb`
- Test: `core_matrix/test/services/canonical_stores/delete_key_test.rb`
- Test: `core_matrix/test/services/variables/promote_to_workspace_test.rb`
- Test: `core_matrix/test/services/human_interactions/request_test.rb`
- Test: `core_matrix/test/services/human_interactions/resolve_approval_test.rb`
- Test: `core_matrix/test/services/human_interactions/submit_form_test.rb`
- Test: `core_matrix/test/services/human_interactions/complete_task_test.rb`
- Test: `core_matrix/test/services/conversations/create_branch_test.rb`
- Test: `core_matrix/test/services/conversations/create_thread_test.rb`
- Test: `core_matrix/test/services/conversations/create_checkpoint_test.rb`
- Test: `core_matrix/test/services/conversations/add_import_test.rb`
- Test: `core_matrix/test/services/conversations/update_override_test.rb`
- Test: `core_matrix/test/services/conversation_summaries/create_segment_test.rb`
- Test: `core_matrix/test/services/messages/update_visibility_test.rb`
- Test: `core_matrix/test/services/turns/edit_tail_input_test.rb`
- Test: `core_matrix/test/services/turns/select_output_variant_test.rb`
- Test: `core_matrix/test/services/turns/retry_output_test.rb`
- Test: `core_matrix/test/services/turns/rerun_output_test.rb`
- Test: `core_matrix/test/services/turns/steer_current_input_test.rb`
- Test: `core_matrix/test/services/conversations/rollback_to_turn_test.rb`
- Test: `core_matrix/test/services/turns/validate_timeline_mutation_target_test.rb`

**Step 1: Write the failing tests**

Add or tighten tests so they prove:

- live mutation paths reject the same blocker states for the same reasons
- timeline mutation paths reuse the same live blocker model plus the explicit
  interrupt fence
- caller tests no longer need to know whether the implementation happens to
  route through `ValidateMutableState`, `WithMutableStateLock`, or
  `WithMutableWorkflowContext`

At minimum, extend one representative test per family so the failure reason is
asserted through the new blocker snapshot semantics instead of bespoke
attribute checks.

Example expectation:

```ruby
test "request rejects live mutation when blocker snapshot says close is in progress" do
  context = build_open_interaction_context_with_closing_conversation!

  error = assert_raises(ActiveRecord::RecordInvalid) do
    HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      request_payload: { "question" => "Proceed?" }
    )
  end

  assert_includes error.record.errors[:base], "must not mutate while close blockers are present"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/turns/start_automation_turn_test.rb \
  test/services/workflows/manual_resume_test.rb \
  test/services/workflows/manual_retry_test.rb \
  test/services/workflows/step_retry_test.rb \
  test/services/canonical_stores/set_test.rb \
  test/services/canonical_stores/delete_key_test.rb \
  test/services/variables/promote_to_workspace_test.rb \
  test/services/human_interactions/request_test.rb \
  test/services/human_interactions/resolve_approval_test.rb \
  test/services/human_interactions/submit_form_test.rb \
  test/services/human_interactions/complete_task_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_thread_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/add_import_test.rb \
  test/services/conversations/update_override_test.rb \
  test/services/conversation_summaries/create_segment_test.rb \
  test/services/messages/update_visibility_test.rb \
  test/services/turns/edit_tail_input_test.rb \
  test/services/turns/select_output_variant_test.rb \
  test/services/turns/retry_output_test.rb \
  test/services/turns/rerun_output_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/conversations/rollback_to_turn_test.rb \
  test/services/turns/validate_timeline_mutation_target_test.rb
```

Expected: FAIL because the shared blocker snapshot is not yet the canonical
source for all live and timeline mutation guards.

**Step 3: Write the minimal implementation**

Implement:

- `ValidateMutableState`
  - evaluate one current blocker snapshot and reject based on its predicates
  - keep retained-state, active-state, and closing-state messaging configurable
    without re-implementing the underlying legality rules
- `WithMutableStateLock`
  - lock once, validate once, and yield the fresh conversation
- `WithMutableWorkflowContext`
  - reuse the shared mutable-state contract instead of carrying local policy
    copies
- `ValidateTimelineMutationTarget`
  - reuse the same live blocker contract, then layer only the interrupt fence on
    top
- `WithTimelineMutationLock`
  - keep lock order deterministic but stop reloading and validating in a second
    bespoke path
- every current live or timeline mutation caller listed above
  - use the shared contracts and stop keeping local lifecycle copies where the
    shared guard can express the rule

After implementation, run a grep audit to confirm the shared guards are now the
only mutation-entry contract family in scope:

```bash
cd core_matrix
rg -n "ValidateMutableState|WithMutableStateLock|ValidateTimelineMutationTarget|WithTimelineMutationLock|WithMutableWorkflowContext" app/services
```

Expected: only the shared guard family and intentional callers remain; no new
parallel helper family was introduced.

**Step 4: Run tests to verify they pass**

Run the same `bin/rails test` command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/validate_mutable_state.rb \
  core_matrix/app/services/conversations/with_mutable_state_lock.rb \
  core_matrix/app/services/workflows/with_mutable_workflow_context.rb \
  core_matrix/app/services/turns/validate_timeline_mutation_target.rb \
  core_matrix/app/services/turns/with_timeline_mutation_lock.rb \
  core_matrix/app/services/turns/start_user_turn.rb \
  core_matrix/app/services/turns/queue_follow_up.rb \
  core_matrix/app/services/turns/start_automation_turn.rb \
  core_matrix/app/services/workflows/manual_resume.rb \
  core_matrix/app/services/workflows/manual_retry.rb \
  core_matrix/app/services/workflows/step_retry.rb \
  core_matrix/app/services/canonical_stores/write_support.rb \
  core_matrix/app/services/variables/promote_to_workspace.rb \
  core_matrix/app/services/human_interactions/request.rb \
  core_matrix/app/services/human_interactions/resolve_approval.rb \
  core_matrix/app/services/human_interactions/submit_form.rb \
  core_matrix/app/services/human_interactions/complete_task.rb \
  core_matrix/app/services/conversations/create_branch.rb \
  core_matrix/app/services/conversations/create_thread.rb \
  core_matrix/app/services/conversations/create_checkpoint.rb \
  core_matrix/app/services/conversations/add_import.rb \
  core_matrix/app/services/conversations/update_override.rb \
  core_matrix/app/services/conversation_summaries/create_segment.rb \
  core_matrix/app/services/messages/update_visibility.rb \
  core_matrix/app/services/turns/steer_current_input.rb \
  core_matrix/app/services/turns/edit_tail_input.rb \
  core_matrix/app/services/turns/select_output_variant.rb \
  core_matrix/app/services/turns/retry_output.rb \
  core_matrix/app/services/turns/rerun_output.rb \
  core_matrix/app/services/conversations/rollback_to_turn.rb \
  core_matrix/test/services/turns/start_user_turn_test.rb \
  core_matrix/test/services/turns/queue_follow_up_test.rb \
  core_matrix/test/services/turns/start_automation_turn_test.rb \
  core_matrix/test/services/workflows/manual_resume_test.rb \
  core_matrix/test/services/workflows/manual_retry_test.rb \
  core_matrix/test/services/workflows/step_retry_test.rb \
  core_matrix/test/services/canonical_stores/set_test.rb \
  core_matrix/test/services/canonical_stores/delete_key_test.rb \
  core_matrix/test/services/variables/promote_to_workspace_test.rb \
  core_matrix/test/services/human_interactions/request_test.rb \
  core_matrix/test/services/human_interactions/resolve_approval_test.rb \
  core_matrix/test/services/human_interactions/submit_form_test.rb \
  core_matrix/test/services/human_interactions/complete_task_test.rb \
  core_matrix/test/services/conversations/create_branch_test.rb \
  core_matrix/test/services/conversations/create_thread_test.rb \
  core_matrix/test/services/conversations/create_checkpoint_test.rb \
  core_matrix/test/services/conversations/add_import_test.rb \
  core_matrix/test/services/conversations/update_override_test.rb \
  core_matrix/test/services/conversation_summaries/create_segment_test.rb \
  core_matrix/test/services/messages/update_visibility_test.rb \
  core_matrix/test/services/turns/edit_tail_input_test.rb \
  core_matrix/test/services/turns/select_output_variant_test.rb \
  core_matrix/test/services/turns/retry_output_test.rb \
  core_matrix/test/services/turns/rerun_output_test.rb \
  core_matrix/test/services/turns/steer_current_input_test.rb \
  core_matrix/test/services/conversations/rollback_to_turn_test.rb \
  core_matrix/test/services/turns/validate_timeline_mutation_target_test.rb
git commit -m "refactor: unify mutation guard contracts"
```

### Task 6: Introduce One Canonical Runtime Capability Contract

**Files:**
- Create: `core_matrix/app/models/runtime_capability_contract.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/app/models/execution_environment.rb`
- Modify: `core_matrix/app/services/execution_environments/record_capabilities.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- Modify: `core_matrix/app/services/agent_deployments/handshake.rb`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Test: `core_matrix/test/models/capability_snapshot_test.rb`
- Test: `core_matrix/test/models/execution_environment_test.rb`
- Test: `core_matrix/test/models/runtime_capability_contract_test.rb`
- Test: `core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`
- Test: `core_matrix/test/services/execution_environments/record_capabilities_test.rb`
- Test: `core_matrix/test/services/runtime_capabilities/compose_for_conversation_test.rb`
- Test: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Test: `core_matrix/test/requests/agent_api/capabilities_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- one contract object can render:
  - environment-plane payload
  - agent-plane payload
  - effective tool catalog
  - conversation-facing runtime capability payload
- handshake and capabilities refresh use the same normalized contract builder
- environment capability payload and tool catalog normalization no longer drift
  between persistence and response rendering

Example expectation:

```ruby
test "capabilities refresh uses the shared runtime capability contract" do
  contract = RuntimeCapabilityContract.build(
    execution_environment: execution_environment,
    capability_snapshot: capability_snapshot
  )

  get agent_api_capabilities_path, headers: authenticated_headers_for(deployment)

  assert_equal contract.effective_tool_catalog, response.parsed_body.fetch("effective_tool_catalog")
  assert_equal contract.environment_plane, response.parsed_body.fetch("environment_plane")
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/capability_snapshot_test.rb \
  test/models/execution_environment_test.rb \
  test/models/runtime_capability_contract_test.rb \
  test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb \
  test/services/execution_environments/record_capabilities_test.rb \
  test/services/runtime_capabilities/compose_for_conversation_test.rb \
  test/services/agent_deployments/handshake_test.rb \
  test/requests/agent_api/capabilities_test.rb
```

Expected: FAIL because the runtime capability contract class does not exist yet
and current rendering still assembles environment and agent planes ad hoc.

**Step 3: Write the minimal implementation**

Implement:

- `RuntimeCapabilityContract`
  - normalize environment payload, environment tool catalog, capability
    snapshot payload, and effective tool catalog in one place
  - expose named projections for handshake or refresh responses and
    conversation-facing capability payloads
- `ExecutionEnvironments::RecordCapabilities`
  - validate and persist environment-plane data through the shared contract
- `CapabilitySnapshot` and `ExecutionEnvironment`
  - keep their own validations, but stop hand-building outward payloads where
    the shared contract can render them
- `ComposeEffectiveToolCatalog` and `ComposeForConversation`
  - become thin users of the shared contract
- `AgentDeployments::Handshake` and `AgentAPI::CapabilitiesController`
  - stop hand-assembling duplicated capability response shapes

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/runtime_capability_contract.rb \
  core_matrix/app/models/capability_snapshot.rb \
  core_matrix/app/models/execution_environment.rb \
  core_matrix/app/services/execution_environments/record_capabilities.rb \
  core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb \
  core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb \
  core_matrix/app/services/agent_deployments/handshake.rb \
  core_matrix/app/controllers/agent_api/capabilities_controller.rb \
  core_matrix/test/models/capability_snapshot_test.rb \
  core_matrix/test/models/execution_environment_test.rb \
  core_matrix/test/models/runtime_capability_contract_test.rb \
  core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb \
  core_matrix/test/services/execution_environments/record_capabilities_test.rb \
  core_matrix/test/services/runtime_capabilities/compose_for_conversation_test.rb \
  core_matrix/test/services/agent_deployments/handshake_test.rb \
  core_matrix/test/requests/agent_api/capabilities_test.rb
git commit -m "refactor: unify runtime capability contracts"
```

### Task 7: Update Behavior Docs And Run Final Verification

**Files:**
- Modify: `core_matrix/docs/behavior/provider-catalog-config-and-validation.md`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/read-side-queries-and-seed-baseline.md`

**Step 1: Update the behavior docs**

Revise the docs so they describe:

- the canonical provider request-setting schema
- the split provider execution path and its stable public entrypoint
- explicit workflow wait snapshots and recovery planning
- the blocker snapshot model that now drives both close summary and mutation
  enforcement
- the shared runtime capability contract used by handshake, refresh, and
  conversation-facing capability payloads

**Step 2: Run the focused verification suite**

Run:

```bash
cd core_matrix
bin/rubocop -f github \
  app/models/provider_request_settings_schema.rb \
  app/models/provider_request_context.rb \
  app/models/workflow_wait_snapshot.rb \
  app/models/agent_deployment_recovery_plan.rb \
  app/models/conversation_blocker_snapshot.rb \
  app/models/runtime_capability_contract.rb \
  app/services/provider_execution \
  app/services/agent_deployments \
  app/services/canonical_stores \
  app/services/conversations \
  app/services/conversation_summaries \
  app/services/messages \
  app/services/turns \
  app/services/variables \
  app/services/workflows \
  app/services/runtime_capabilities \
  app/queries/conversations \
  app/controllers/agent_api/capabilities_controller.rb \
  test/models/capability_snapshot_test.rb \
  test/models/execution_environment_test.rb \
  test/models/provider_request_settings_schema_test.rb \
  test/models/provider_request_context_test.rb \
  test/models/workflow_wait_snapshot_test.rb \
  test/models/agent_deployment_recovery_plan_test.rb \
  test/models/conversation_blocker_snapshot_test.rb \
  test/models/runtime_capability_contract_test.rb \
  test/services/provider_execution \
  test/services/agent_deployments \
  test/services/canonical_stores \
  test/services/conversation_summaries \
  test/services/turns \
  test/services/workflows \
  test/services/human_interactions \
  test/services/conversations \
  test/services/messages \
  test/services/runtime_capabilities \
  test/services/execution_environments \
  test/services/variables \
  test/queries/conversations \
  test/requests/agent_api/capabilities_test.rb
bin/rails test \
  test/services/provider_execution \
  test/services/agent_deployments \
  test/services/canonical_stores \
  test/services/conversation_summaries \
  test/services/turns \
  test/services/workflows \
  test/services/human_interactions \
  test/services/conversations \
  test/services/messages \
  test/services/runtime_capabilities \
  test/services/execution_environments \
  test/services/variables \
  test/models/capability_snapshot_test.rb \
  test/models/execution_environment_test.rb \
  test/queries/conversations \
  test/requests/agent_api/capabilities_test.rb
```

Expected: PASS.

**Step 3: Run the final structural grep checks**

Run:

```bash
cd core_matrix
rg -n "EXECUTION_SETTING_KEYS" app test
rg -n "paused_wait_snapshot|SNAPSHOT_KEY" app test
rg -n "active_turn_count|open_blocking_interaction_count|degraded_close_count" app/services app/queries
```

Expected:

- no remaining `EXECUTION_SETTING_KEYS` references
- wait-snapshot internals only remain inside the new wait-snapshot contract
  family
- close-summary counters only remain inside the blocker snapshot query or
  projection layer, not re-encoded in multiple services

**Step 4: Run the repository verification baseline for Ruby code**

Run:

```bash
cd core_matrix
bin/rails db:test:prepare test
```

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/docs/behavior/provider-catalog-config-and-validation.md \
  core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md \
  core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  core_matrix/docs/behavior/conversation-structure-and-lineage.md \
  core_matrix/docs/behavior/agent-registration-and-capability-handshake.md \
  core_matrix/docs/behavior/agent-runtime-resource-apis.md \
  core_matrix/docs/behavior/read-side-queries-and-seed-baseline.md
git commit -m "docs: record structural consolidation contracts"
```
