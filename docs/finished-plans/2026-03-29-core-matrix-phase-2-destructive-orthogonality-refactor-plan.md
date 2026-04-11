# Core Matrix Phase 2 Destructive Orthogonality Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Execute a three-batch destructive refactor that makes recovery ownership, mutation guard entrypoints, and read-side object types explicit and orthogonal in `core_matrix`.

**Architecture:** Batch 1 centralizes paused-work recovery planning and rebinding without widening persisted compatibility semantics. Batch 2 deletes duplicate mutation wrappers and keeps only intent-shaped guard entrypoints over the shared blocker snapshot. Batch 3 splits read-side objects by type, moving projections and resolvers out of `app/queries` and deleting thin blocker-summary query wrappers once callers can read the blocker snapshot directly.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record, plain Ruby value objects under `app/models`, Minitest, behavior docs under `core_matrix/docs/behavior`, `rg`, `bin/rails test`, `bin/rubocop`

---

## Execution Rules

- Treat this as a destructive refactor plan. Do not add compatibility aliases.
- If a batch needs durable model or field changes to make the new owner real,
  rewrite the original migration, regenerate `db/schema.rb`, and reset the
  database baseline inside that batch.
- Every batch must finish with:
  - code-path grep checks
  - touched behavior docs updated
  - targeted tests green
  - one adjacent integration surface green
- Do not start the next batch until the previous batch has removed the old
  production call path and the old tests.
- Keep generic live-conversation contracts separate from paused-work recovery
  contracts.
- Keep read-side naming cleanup out of Batches 1 and 2 unless a read-side file
  is directly required to delete an old writer or wrapper.

## Task 1: Lock The Batch 1 Recovery File Map And Failing Tests

**Files:**
- Modify: `core_matrix/test/models/agent_deployment_recovery_plan_test.rb`
- Create: `core_matrix/test/models/agent_deployment_recovery_target_test.rb`
- Modify: `core_matrix/test/services/agent_deployments/build_recovery_plan_test.rb`
- Modify: `core_matrix/test/services/agent_deployments/apply_recovery_plan_test.rb`
- Modify: `core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb`
- Create: `core_matrix/test/services/agent_deployments/resolve_recovery_target_test.rb`
- Create: `core_matrix/test/services/agent_deployments/rebind_turn_test.rb`
- Modify: `core_matrix/test/services/workflows/manual_resume_test.rb`
- Modify: `core_matrix/test/services/workflows/manual_retry_test.rb`
- Modify: `core_matrix/test/services/conversations/validate_agent_deployment_target_test.rb`
- Modify: `core_matrix/test/services/conversations/switch_agent_deployment_test.rb`
- Modify: `core_matrix/test/integration/agent_recovery_flow_test.rb`

**Step 1: Write the failing planner and rebinding expectations**

Add or tighten tests that prove:

- paused-work target resolution has one canonical owner
- `ApplyRecoveryPlan` does not re-resolve recovery targets on its own
- `Workflows::ManualResume` uses the same rebinding mutation path as auto
  resume
- `Workflows::ManualRetry` uses the same paused-work target-resolution contract
  as the recovery planner instead of revalidating paused compatibility through a
  separate shape
- generic conversation deployment switching remains separate from paused-work
  recovery checks

Example expectation:

```ruby
test "manual resume and apply recovery plan share the same turn rebinding path" do
  # expect one recovery target object and one rebinding service to own the write
end
```

**Step 2: Run the targeted recovery tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/models/agent_deployment_recovery_target_test.rb \
  test/services/agent_deployments/build_recovery_plan_test.rb \
  test/services/agent_deployments/apply_recovery_plan_test.rb \
  test/services/agent_deployments/auto_resume_workflows_test.rb \
  test/services/agent_deployments/resolve_recovery_target_test.rb \
  test/services/agent_deployments/rebind_turn_test.rb \
  test/services/workflows/manual_resume_test.rb \
  test/services/workflows/manual_retry_test.rb \
  test/services/conversations/validate_agent_deployment_target_test.rb \
  test/services/conversations/switch_agent_deployment_test.rb \
  test/integration/agent_recovery_flow_test.rb
```

Expected: FAIL because recovery resolution and turn rebinding are still split
across planner, applier, and manual resume paths.

## Task 2: Implement Batch 1 Recovery Target And Rebinding Owners

**Files:**
- Create: `core_matrix/app/models/agent_deployment_recovery_target.rb`
- Create: `core_matrix/app/services/agent_deployments/resolve_recovery_target.rb`
- Create: `core_matrix/app/services/agent_deployments/rebind_turn.rb`
- Delete: `core_matrix/app/services/agent_deployments/validate_recovery_target.rb`
- Modify: `core_matrix/app/models/agent_deployment_recovery_plan.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/app/services/agent_deployments/build_recovery_plan.rb`
- Modify: `core_matrix/app/services/agent_deployments/apply_recovery_plan.rb`
- Modify: `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
- Modify: `core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `core_matrix/app/services/workflows/manual_retry.rb`
- Modify: `core_matrix/app/services/conversations/validate_agent_deployment_target.rb`
- Modify: `core_matrix/app/services/conversations/switch_agent_deployment.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify tests from Task 1

**Step 1: Write the minimal recovery target value object**

Implement a value object that carries:

- target deployment
- resolved model-selection snapshot
- selector source
- whether rebinding is required

**Step 2: Move paused-work compatibility and selector resolution into one service**

Implement `AgentDeployments::ResolveRecoveryTarget` so it owns:

- schedulable checks
- optional auto-resume eligibility checks
- paused-work same-environment and same-logical-agent checks
- paused capability-contract compatibility
- selector re-resolution on the candidate deployment

**Step 3: Move rebinding writes into one service**

Implement `AgentDeployments::RebindTurn` so it owns:

- switching the conversation deployment
- updating `turn.agent_deployment`
- updating `turn.pinned_deployment_fingerprint`
- updating `turn.resolved_model_selection_snapshot`
- rebuilding `turn.execution_snapshot_payload`

**Step 4: Make the public orchestrators thin**

Refactor:

- `BuildRecoveryPlan` to plan only
- `ApplyRecoveryPlan` to call the new rebinding service when the plan demands
  rebinding
- `Workflows::ManualResume` to resolve a recovery target and then use the same
  rebinding service
- `Workflows::ManualRetry` to reuse the paused-work recovery target-resolution
  contract without introducing a separate paused-compatibility path
- `ValidateRecoveryTarget` either into a thin delegator or delete it if
  `ResolveRecoveryTarget` fully replaces it

**Step 5: Run the targeted tests and confirm PASS**

Run the same command from Task 1.

Expected: PASS.

**Step 6: Commit**

```bash
git add core_matrix/app/models/agent_deployment_recovery_target.rb \
  core_matrix/app/services/agent_deployments/resolve_recovery_target.rb \
  core_matrix/app/services/agent_deployments/rebind_turn.rb \
  core_matrix/app/models/agent_deployment_recovery_plan.rb \
  core_matrix/app/models/agent_deployment.rb \
  core_matrix/app/services/agent_deployments/build_recovery_plan.rb \
  core_matrix/app/services/agent_deployments/apply_recovery_plan.rb \
  core_matrix/app/services/agent_deployments/validate_recovery_target.rb \
  core_matrix/app/services/agent_deployments/auto_resume_workflows.rb \
  core_matrix/app/services/workflows/manual_resume.rb \
  core_matrix/app/services/workflows/manual_retry.rb \
  core_matrix/app/services/conversations/validate_agent_deployment_target.rb \
  core_matrix/app/services/conversations/switch_agent_deployment.rb \
  core_matrix/app/services/workflows/build_execution_snapshot.rb \
  core_matrix/test/models/agent_deployment_recovery_target_test.rb \
  core_matrix/test/models/agent_deployment_recovery_plan_test.rb \
  core_matrix/test/services/agent_deployments/build_recovery_plan_test.rb \
  core_matrix/test/services/agent_deployments/apply_recovery_plan_test.rb \
  core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb \
  core_matrix/test/services/agent_deployments/resolve_recovery_target_test.rb \
  core_matrix/test/services/agent_deployments/rebind_turn_test.rb \
  core_matrix/test/services/workflows/manual_resume_test.rb \
  core_matrix/test/services/workflows/manual_retry_test.rb \
  core_matrix/test/services/conversations/validate_agent_deployment_target_test.rb \
  core_matrix/test/services/conversations/switch_agent_deployment_test.rb \
  core_matrix/test/integration/agent_recovery_flow_test.rb
git commit -m "refactor: centralize recovery and rebinding ownership"
```

## Task 3: Close Batch 1 With Docs, Grep Checks, And Adjacent Verification

**Files:**
- Modify: `core_matrix/docs/behavior/agent-snapshot-bootstrap-and-recovery-flows.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`

**Step 1: Update the behavior docs**

Describe:

- the new paused-work recovery target owner
- the new rebinding mutation owner
- the distinction between generic conversation deployment switching and paused
  workflow recovery

**Step 2: Run stale-path grep checks**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "ValidateRecoveryTarget.call|resolved_model_selection_snapshot: Workflows::BuildExecutionSnapshot|pinned_deployment_fingerprint: .*fingerprint" core_matrix/app core_matrix/test
```

Expected: only the new canonical recovery path or intentionally retained model
attribute writes appear.

**Step 3: Run the batch-local plus adjacent integration verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/services/agent_deployments \
  test/services/workflows/manual_resume_test.rb \
  test/services/workflows/manual_retry_test.rb \
  test/services/conversations/validate_agent_deployment_target_test.rb \
  test/integration/agent_recovery_flow_test.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add core_matrix/docs/behavior/agent-snapshot-bootstrap-and-recovery-flows.md \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  core_matrix/docs/behavior/agent-registration-and-capability-handshake.md
git commit -m "docs: describe centralized recovery ownership"
```

## Task 4: Lock The Batch 2 Wrapper-Deletion Tests

**Files:**
- Create: `core_matrix/test/services/conversations/validate_mutable_state_test.rb`
- Create: `core_matrix/test/services/conversations/with_mutable_state_lock_test.rb`
- Create: `core_matrix/test/services/conversations/with_retained_state_lock_test.rb`
- Modify: `core_matrix/test/services/conversations/with_conversation_entry_lock_test.rb`
- Modify: `core_matrix/test/services/conversations/with_retained_lifecycle_lock_test.rb`
- Modify: `core_matrix/test/services/conversations/validate_quiescence_test.rb`
- Modify: `core_matrix/test/services/conversations/finalize_deletion_test.rb`
- Create: `core_matrix/test/services/turns/with_timeline_mutation_lock_test.rb`
- Modify: `core_matrix/test/services/turns/validate_timeline_mutation_target_test.rb`
- Modify: `core_matrix/test/services/conversations/archive_test.rb`
- Modify: `core_matrix/test/services/conversations/purge_deleted_test.rb`
- Create: `core_matrix/test/services/conversations/request_close_test.rb`
- Modify: `core_matrix/test/services/conversations/request_deletion_test.rb`
- Modify: `core_matrix/test/services/conversations/rollback_to_turn_test.rb`
- Modify: `core_matrix/test/services/publications/publish_live_test.rb`

**Step 1: Write failing tests that prove only canonical wrappers remain**

Add or tighten tests so they expect:

- direct unit coverage for each surviving public wrapper
- deleted wrapper names no longer exist
- quiescence is called through the canonical validator path

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/services/conversations/validate_mutable_state_test.rb \
  test/services/conversations/with_mutable_state_lock_test.rb \
  test/services/conversations/with_retained_state_lock_test.rb \
  test/services/conversations/with_conversation_entry_lock_test.rb \
  test/services/conversations/with_retained_lifecycle_lock_test.rb \
  test/services/conversations/validate_quiescence_test.rb \
  test/services/turns/with_timeline_mutation_lock_test.rb \
  test/services/turns/validate_timeline_mutation_target_test.rb \
  test/services/conversations/archive_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/services/conversations/request_close_test.rb \
  test/services/conversations/request_deletion_test.rb \
  test/services/conversations/rollback_to_turn_test.rb \
  test/services/publications/publish_live_test.rb
```

Expected: FAIL because alias wrappers and helper modules still exist.

## Task 5: Implement Batch 2 Canonical Guard Surface

**Files:**
- Delete: `core_matrix/app/services/turns/with_conversation_entry_lock.rb`
- Delete: `core_matrix/app/services/turns/with_timeline_action_lock.rb`
- Delete: `core_matrix/app/services/conversations/work_quiescence_guard.rb`
- Delete: `core_matrix/test/services/turns/with_conversation_entry_lock_test.rb`
- Delete: `core_matrix/test/services/turns/with_timeline_action_lock_test.rb`
- Modify: `core_matrix/app/models/conversation_blocker_snapshot.rb`
- Modify if needed: `core_matrix/test/models/conversation_blocker_snapshot_test.rb`
- Modify: `core_matrix/app/services/conversations/validate_mutable_state.rb`
- Modify: `core_matrix/app/services/conversations/with_mutable_state_lock.rb`
- Modify: `core_matrix/app/services/conversations/with_conversation_entry_lock.rb`
- Modify: `core_matrix/app/services/conversations/with_retained_state_lock.rb`
- Modify: `core_matrix/app/services/conversations/with_retained_lifecycle_lock.rb`
- Modify: `core_matrix/app/services/conversations/validate_quiescence.rb`
- Modify: `core_matrix/app/services/workflows/with_mutable_workflow_context.rb`
- Modify: `core_matrix/app/services/turns/with_timeline_mutation_lock.rb`
- Modify: `core_matrix/app/services/turns/validate_timeline_mutation_target.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/start_agent_turn.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Modify: `core_matrix/app/services/turns/retry_output.rb`
- Modify: `core_matrix/app/services/turns/select_output_variant.rb`
- Modify: `core_matrix/app/services/turns/edit_tail_input.rb`
- Modify: `core_matrix/app/services/turns/rerun_output.rb`
- Modify: `core_matrix/app/services/conversations/rollback_to_turn.rb`
- Modify: `core_matrix/app/services/conversations/archive.rb`
- Modify: `core_matrix/app/services/conversations/finalize_deletion.rb`
- Modify: `core_matrix/app/services/conversations/purge_deleted.rb`
- Modify: `core_matrix/app/services/conversations/request_close.rb`
- Modify: `core_matrix/app/services/publications/publish_live.rb`
- Modify tests from Task 4

**Step 1: Move callsites to the surviving wrappers**

Replace:

- `Turns::WithConversationEntryLock` with
  `Conversations::WithConversationEntryLock`
- `Turns::WithTimelineActionLock` with `Turns::WithTimelineMutationLock`
- `Conversations::WorkQuiescenceGuard` includes with direct
  `Conversations::ValidateQuiescence` calls

**Step 2: Delete the alias wrappers and their tests**

Delete the three wrapper files once no production caller depends on them, and
delete the obsolete alias-wrapper test files in the same batch.

**Step 3: Keep blocker facts centralized**

Adjust `ConversationBlockerSnapshot` and its tests only if needed to keep
message mapping and blocker readers explicit after callsite cleanup.

**Step 4: Run the targeted tests and confirm PASS**

Run the same command from Task 4.

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/conversation_blocker_snapshot.rb \
  core_matrix/app/services/conversations/validate_mutable_state.rb \
  core_matrix/app/services/conversations/with_mutable_state_lock.rb \
  core_matrix/app/services/conversations/with_conversation_entry_lock.rb \
  core_matrix/app/services/conversations/with_retained_state_lock.rb \
  core_matrix/app/services/conversations/with_retained_lifecycle_lock.rb \
  core_matrix/app/services/conversations/validate_quiescence.rb \
  core_matrix/app/services/workflows/with_mutable_workflow_context.rb \
  core_matrix/app/services/turns/with_timeline_mutation_lock.rb \
  core_matrix/app/services/turns/validate_timeline_mutation_target.rb \
  core_matrix/app/services/turns/start_user_turn.rb \
  core_matrix/app/services/turns/start_agent_turn.rb \
  core_matrix/app/services/turns/start_automation_turn.rb \
  core_matrix/app/services/turns/queue_follow_up.rb \
  core_matrix/app/services/turns/steer_current_input.rb \
  core_matrix/app/services/turns/retry_output.rb \
  core_matrix/app/services/turns/select_output_variant.rb \
  core_matrix/app/services/turns/edit_tail_input.rb \
  core_matrix/app/services/turns/rerun_output.rb \
  core_matrix/app/services/conversations/rollback_to_turn.rb \
  core_matrix/app/services/conversations/archive.rb \
  core_matrix/app/services/conversations/finalize_deletion.rb \
  core_matrix/app/services/conversations/purge_deleted.rb \
  core_matrix/app/services/conversations/request_close.rb \
  core_matrix/app/services/publications/publish_live.rb \
  core_matrix/test/services/conversations/validate_mutable_state_test.rb \
  core_matrix/test/services/conversations/with_mutable_state_lock_test.rb \
  core_matrix/test/services/conversations/with_retained_state_lock_test.rb \
  core_matrix/test/services/conversations/with_conversation_entry_lock_test.rb \
  core_matrix/test/services/conversations/with_retained_lifecycle_lock_test.rb \
  core_matrix/test/services/conversations/validate_quiescence_test.rb \
  core_matrix/test/services/conversations/finalize_deletion_test.rb \
  core_matrix/test/services/turns/with_timeline_mutation_lock_test.rb \
  core_matrix/test/services/turns/validate_timeline_mutation_target_test.rb \
  core_matrix/test/services/conversations/archive_test.rb \
  core_matrix/test/services/conversations/purge_deleted_test.rb \
  core_matrix/test/services/conversations/request_close_test.rb \
  core_matrix/test/services/conversations/request_deletion_test.rb \
  core_matrix/test/services/conversations/rollback_to_turn_test.rb \
  core_matrix/test/services/publications/publish_live_test.rb
git add -u core_matrix/app/services/turns/with_conversation_entry_lock.rb \
  core_matrix/app/services/turns/with_timeline_action_lock.rb \
  core_matrix/app/services/conversations/work_quiescence_guard.rb \
  core_matrix/test/services/turns/with_conversation_entry_lock_test.rb \
  core_matrix/test/services/turns/with_timeline_action_lock_test.rb
git commit -m "refactor: collapse mutation guard wrappers"
```

## Task 6: Close Batch 2 With Docs, Grep Checks, And Adjacent Verification

**Files:**
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/publication-and-live-projection.md`

**Step 1: Update behavior docs**

Document:

- the surviving mutation wrapper family
- direct quiescence validation usage
- the deleted alias wrappers as removed concepts

**Step 2: Run stale-path grep checks**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "Turns::WithConversationEntryLock|Turns::WithTimelineActionLock|WorkQuiescenceGuard" core_matrix/app core_matrix/test
```

Expected: no matches.

**Step 3: Run batch-local plus adjacent integration verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/services/conversations \
  test/services/turns \
  test/services/workflows/manual_resume_test.rb \
  test/integration/publication_flow_test.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add core_matrix/docs/behavior/conversation-structure-and-lineage.md \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  core_matrix/docs/behavior/publication-and-live-projection.md
git commit -m "docs: describe canonical mutation guard contracts"
```

## Task 7: Lock The Batch 3 Read-Side Type Split Tests

**Files:**
- Create: `core_matrix/test/projections/conversation_transcripts/page_projection_test.rb`
- Create: `core_matrix/test/projections/publications/live_projection_test.rb`
- Create: `core_matrix/test/projections/workflows/projection_test.rb`
- Create: `core_matrix/test/resolvers/conversation_variables/visible_values_resolver_test.rb`
- Modify: `core_matrix/test/queries/conversations/blocker_snapshot_query_test.rb`
- Modify: `core_matrix/test/integration/canonical_variable_flow_test.rb`
- Modify: `core_matrix/test/integration/publication_flow_test.rb`
- Modify: `core_matrix/test/integration/workflow_yield_materialization_flow_test.rb`

**Step 1: Write failing tests for the renamed type boundaries**

Adjust tests so they expect:

- projection classes under `app/projections` with matching direct tests
- resolver classes under `app/resolvers` with matching direct tests
- no thin blocker-summary query wrappers

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/projections/conversation_transcripts/page_projection_test.rb \
  test/projections/publications/live_projection_test.rb \
  test/projections/workflows/projection_test.rb \
  test/resolvers/conversation_variables/visible_values_resolver_test.rb \
  test/queries/conversations/blocker_snapshot_query_test.rb \
  test/integration/canonical_variable_flow_test.rb \
  test/integration/publication_flow_test.rb \
  test/integration/workflow_yield_materialization_flow_test.rb
```

Expected: FAIL because the new projection and resolver classes do not exist yet
and the old `*Query` classes still exist.

## Task 8: Implement Batch 3 Read-Side Type Split

**Files:**
- Create: `core_matrix/app/projections/conversation_transcripts/page_projection.rb`
- Create: `core_matrix/app/projections/publications/live_projection.rb`
- Create: `core_matrix/app/projections/workflows/projection.rb`
- Create: `core_matrix/app/resolvers/conversation_variables/visible_values_resolver.rb`
- Delete: `core_matrix/app/queries/conversation_variables/resolve_query.rb`
- Delete: `core_matrix/app/queries/conversation_transcripts/list_query.rb`
- Delete: `core_matrix/app/queries/publications/live_projection_query.rb`
- Delete: `core_matrix/app/queries/workflows/projection_query.rb`
- Delete: `core_matrix/app/queries/conversations/work_barrier_query.rb`
- Delete: `core_matrix/app/queries/conversations/close_summary_query.rb`
- Delete: `core_matrix/app/queries/conversations/dependency_blockers_query.rb`
- Delete: `core_matrix/test/queries/conversation_variables/resolve_query_test.rb`
- Delete: `core_matrix/test/queries/conversation_transcripts/list_query_test.rb`
- Delete: `core_matrix/test/queries/publications/live_projection_query_test.rb`
- Delete: `core_matrix/test/queries/conversations/work_barrier_query_test.rb`
- Delete: `core_matrix/test/queries/conversations/close_summary_query_test.rb`
- Delete: `core_matrix/test/queries/conversations/dependency_blockers_query_test.rb`
- Modify: `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- Modify: `core_matrix/app/controllers/agent_api/conversation_variables_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/conversation_transcripts_controller.rb`
- Modify: `core_matrix/app/services/conversations/validate_quiescence.rb`
- Modify: `core_matrix/app/services/conversations/validate_timeline_suffix_supersession.rb`
- Modify: `core_matrix/app/services/conversations/purge_deleted.rb`
- Modify tests from Task 7

**Step 1: Move the projection and resolver classes**

Implement the new classes and migrate the logic from the deleted `*Query`
files into them without changing behavior.

**Step 2: Delete thin blocker-summary query wrappers**

Update callers to use:

- `Conversations::BlockerSnapshotQuery.call(...).work_barrier`
- `Conversations::BlockerSnapshotQuery.call(...).close_summary`
- `Conversations::BlockerSnapshotQuery.call(...).dependency_blockers`

or a cached local snapshot object, instead of wrapper query classes.

**Step 3: Move and prune the read-side tests**

Move direct tests to the new `test/projections` and `test/resolvers`
directories, expand `blocker_snapshot_query_test.rb` to cover the surviving
snapshot readers, and delete the obsolete wrapper-query tests in the same
batch.

**Step 4: Update controller and integration call sites**

Move API and integration callers to the renamed projection and resolver
classes.

**Step 5: Run the targeted tests and confirm PASS**

Run the same command from Task 7.

Expected: PASS.

**Step 6: Commit**

```bash
git add core_matrix/app/projections/conversation_transcripts/page_projection.rb \
  core_matrix/app/projections/publications/live_projection.rb \
  core_matrix/app/projections/workflows/projection.rb \
  core_matrix/app/resolvers/conversation_variables/visible_values_resolver.rb \
  core_matrix/app/queries/conversations/blocker_snapshot_query.rb \
  core_matrix/app/controllers/agent_api/conversation_variables_controller.rb \
  core_matrix/app/controllers/agent_api/conversation_transcripts_controller.rb \
  core_matrix/app/services/conversations/validate_quiescence.rb \
  core_matrix/app/services/conversations/validate_timeline_suffix_supersession.rb \
  core_matrix/app/services/conversations/purge_deleted.rb \
  core_matrix/test/projections/conversation_transcripts/page_projection_test.rb \
  core_matrix/test/projections/publications/live_projection_test.rb \
  core_matrix/test/projections/workflows/projection_test.rb \
  core_matrix/test/resolvers/conversation_variables/visible_values_resolver_test.rb \
  core_matrix/test/queries/conversations/blocker_snapshot_query_test.rb \
  core_matrix/test/integration/canonical_variable_flow_test.rb \
  core_matrix/test/integration/publication_flow_test.rb \
  core_matrix/test/integration/workflow_yield_materialization_flow_test.rb
git add -u core_matrix/app/queries/conversation_variables/resolve_query.rb \
  core_matrix/app/queries/conversation_transcripts/list_query.rb \
  core_matrix/app/queries/publications/live_projection_query.rb \
  core_matrix/app/queries/workflows/projection_query.rb \
  core_matrix/app/queries/conversations/work_barrier_query.rb \
  core_matrix/app/queries/conversations/close_summary_query.rb \
  core_matrix/app/queries/conversations/dependency_blockers_query.rb \
  core_matrix/test/queries/conversation_variables/resolve_query_test.rb \
  core_matrix/test/queries/conversation_transcripts/list_query_test.rb \
  core_matrix/test/queries/publications/live_projection_query_test.rb \
  core_matrix/test/queries/conversations/work_barrier_query_test.rb \
  core_matrix/test/queries/conversations/close_summary_query_test.rb \
  core_matrix/test/queries/conversations/dependency_blockers_query_test.rb
git commit -m "refactor: split read-side objects by type"
```

## Task 9: Close Batch 3 With Docs, Grep Checks, And Full Verification

**Files:**
- Modify: `core_matrix/docs/behavior/publication-and-live-projection.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/canonical-variable-history-and-promotion.md`

**Step 1: Update behavior docs**

Describe:

- which read-side families are queries, projections, and resolvers
- that blocker-summary wrapper queries are gone
- the new projection and resolver owners used by API and integration surfaces

**Step 2: Run stale-path grep checks**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "ResolveQuery|ListQuery|LiveProjectionQuery|ProjectionQuery|WorkBarrierQuery|CloseSummaryQuery|DependencyBlockersQuery" core_matrix/app core_matrix/test
```

Expected: only intentionally retained pure query classes remain, and none of
the deleted class names listed in this batch appear.

**Step 3: Run final verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/services/agent_deployments \
  test/services/conversations \
  test/services/turns \
  test/services/workflows \
  test/services/runtime_capabilities \
  test/services/subagent_connections \
  test/services/provider_execution \
  test/projections \
  test/resolvers \
  test/models/agent_deployment_recovery_target_test.rb \
  test/models/agent_deployment_recovery_plan_test.rb \
  test/models/conversation_blocker_snapshot_test.rb \
  test/models/runtime_capability_contract_test.rb \
  test/models/capability_snapshot_test.rb \
  test/models/subagent_connection_test.rb \
  test/queries/conversations \
  test/queries/workspace_variables \
  test/queries/lineage_stores \
  test/requests/agent_api \
  test/integration/agent_recovery_flow_test.rb \
  test/integration/canonical_variable_flow_test.rb \
  test/integration/publication_flow_test.rb \
  test/integration/workflow_yield_materialization_flow_test.rb
bin/rubocop \
  app/models \
  app/services/agent_deployments \
  app/services/conversations \
  app/services/turns \
  app/services/workflows \
  app/services/runtime_capabilities \
  app/services/subagent_connections \
  app/services/provider_execution \
  app/projections \
  app/resolvers \
  app/queries \
  app/controllers/agent_api \
  test/services/agent_deployments \
  test/services/conversations \
  test/services/turns \
  test/services/workflows \
  test/services/runtime_capabilities \
  test/services/subagent_connections \
  test/services/provider_execution \
  test/models \
  test/queries \
  test/requests/agent_api \
  test/integration
git diff --check
git status --short
```

Expected:

- all tests PASS
- RuboCop exits `0`
- `git diff --check` reports no whitespace errors
- `git status --short` shows only the intended tracked changes

**Step 4: Commit**

```bash
git add core_matrix/docs/behavior/publication-and-live-projection.md \
  core_matrix/docs/behavior/conversation-structure-and-lineage.md \
  core_matrix/docs/behavior/canonical-variable-history-and-promotion.md
git commit -m "docs: describe orthogonal read-side contracts"
```

## Execution Readiness

Plan complete and saved to
`docs/plans/2026-03-29-core-matrix-phase-2-destructive-orthogonality-refactor-plan.md`.

Recommended execution order remains:

1. Batch 1: recovery and rebinding owner cleanup
2. Batch 2: mutation guard contract cleanup
3. Batch 3: read-side type split

Do not overlap batches. Each batch closes only after its stale-path grep
checks, touched docs, targeted tests, and adjacent integration verification are
green.
