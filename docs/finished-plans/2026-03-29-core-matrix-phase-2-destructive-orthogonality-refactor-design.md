# Core Matrix Phase 2 Destructive Orthogonality Refactor Design

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/finished-plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
4. `docs/finished-plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`
5. `docs/finished-plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
6. `core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md`
7. `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
8. `core_matrix/docs/behavior/subagent-sessions-and-execution-leases.md`
9. `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
10. `core_matrix/docs/behavior/publication-and-live-projection.md`

## Purpose

Run one deliberate three-batch destructive refactor that corrects the remaining
concept drift found after Phase 2 Milestone C follow-up hardening.

This is not a compatibility batch. The goal is to make the current architecture
more explicit and more orthogonal by deleting duplicate owners, deleting thin
duplicate wrappers, and renaming or relocating read-side objects whose current
names no longer describe what they are.

## Hard Constraints

- This work is allowed to be destructive between batches.
- Each batch must end in a stable state with updated tests and updated behavior
  docs.
- Do not keep compatibility shims, legacy aliases, or duplicate owners after a
  batch completes.
- If a batch needs model or field changes to make the new owner real, rewrite
  the original migration, regenerate `db/schema.rb`, and reset the database
  baseline inside that batch.
- Do not leave old production call paths or tests pointing at deleted concepts.
- Every batch must finish with a code-and-doc sweep that proves the old shape
  has actually disappeared.

## Why Three Batches

The three topics are related, but they are not the same kind of problem.

1. Recovery and rebinding are write-side authority problems.
2. Mutation guards are write-side contract-entry and naming problems.
3. Query cleanup is a read-side type and naming problem.

That ordering matters. The first two batches simplify write-side ownership and
entrypoints before the third batch renames or relocates read-side objects that
depend on those contracts.

## Batch Order

### Batch 1: Recovery / Rebind Single Owner

#### Objective

Collapse paused-work recovery and deployment rebinding onto one canonical
recovery contract family.

After this batch:

- compatibility and selector-resolution checks for paused work have one
  canonical owner
- turn rebinding and execution-snapshot rebuild have one canonical mutation
  owner
- auto-resume and manual resume reuse the same target-resolution and rebinding
  path instead of replaying the same edits independently
- generic live conversation deployment switching stays separate from paused
  workflow recovery

#### Target Shape

- Keep `Conversations::ValidateAgentDeploymentTarget` as the generic validator
  for live conversation deployment switching only.
- Keep `AgentDeploymentRecoveryPlan` as the public planner result.
- Introduce one paused-work target-resolution contract that owns:
  - schedulable and auto-resume checks
  - same-environment and same-logical-agent enforcement for paused work
  - paused capability-contract compatibility
  - selector re-resolution for the replacement deployment
- Introduce one rebinding mutation contract that owns:
  - switching the conversation deployment
  - updating turn deployment pinning
  - replacing the resolved model-selection snapshot
  - rebuilding the turn execution snapshot
- Make `BuildRecoveryPlan`, `ApplyRecoveryPlan`, and `Workflows::ManualResume`
  thin orchestrators over those contracts.

#### Important Non-Goal

Do not widen paused-work continuity beyond what the current system can already
verify durably. The current code has a durable paused agent-plane capability
anchor and a durable execution-environment binding, but it does not yet persist
an environment-plane capability snapshot for paused turns. This batch should
centralize the owner, not silently invent a second hidden compatibility rule.

#### Production Files In Scope

- `core_matrix/app/models/agent_deployment.rb`
- `core_matrix/app/models/agent_deployment_recovery_plan.rb`
- `core_matrix/app/models/runtime_capability_contract.rb`
- `core_matrix/app/models/capability_snapshot.rb`
- `core_matrix/app/services/agent_deployments/build_recovery_plan.rb`
- `core_matrix/app/services/agent_deployments/apply_recovery_plan.rb`
- `core_matrix/app/services/agent_deployments/validate_recovery_target.rb`
- `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
- `core_matrix/app/services/agent_deployments/mark_unavailable.rb`
- `core_matrix/app/services/workflows/manual_resume.rb`
- `core_matrix/app/services/workflows/manual_retry.rb`
- `core_matrix/app/services/conversations/validate_agent_deployment_target.rb`
- `core_matrix/app/services/conversations/switch_agent_deployment.rb`
- `core_matrix/app/services/workflows/build_execution_snapshot.rb`

#### Files Expected To Be Added

- `core_matrix/app/models/agent_deployment_recovery_target.rb`
- `core_matrix/app/services/agent_deployments/resolve_recovery_target.rb`
- `core_matrix/app/services/agent_deployments/rebind_turn.rb`

#### Files Expected To Be Deleted

- `core_matrix/app/services/agent_deployments/validate_recovery_target.rb`

#### Test Files In Scope

- `core_matrix/test/models/agent_deployment_recovery_plan_test.rb`
- `core_matrix/test/models/runtime_capability_contract_test.rb`
- `core_matrix/test/models/capability_snapshot_test.rb`
- `core_matrix/test/services/agent_deployments/build_recovery_plan_test.rb`
- `core_matrix/test/services/agent_deployments/apply_recovery_plan_test.rb`
- `core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb`
- `core_matrix/test/services/agent_deployments/mark_unavailable_test.rb`
- `core_matrix/test/services/workflows/manual_resume_test.rb`
- `core_matrix/test/services/workflows/manual_retry_test.rb`
- `core_matrix/test/services/conversations/validate_agent_deployment_target_test.rb`
- `core_matrix/test/services/conversations/switch_agent_deployment_test.rb`
- `core_matrix/test/integration/agent_recovery_flow_test.rb`

#### Test Files Expected To Be Added

- `core_matrix/test/models/agent_deployment_recovery_target_test.rb`
- `core_matrix/test/services/agent_deployments/resolve_recovery_target_test.rb`
- `core_matrix/test/services/agent_deployments/rebind_turn_test.rb`

#### Behavior Docs To Update

- `core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md`
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`

#### Batch 1 Confirmation List

Before closing Batch 1, confirm all of the following:

- no production code outside the new recovery-target contract is still
  resolving paused recovery compatibility by hand
- no production code outside the new rebinding mutation contract is still
  rewriting turn deployment pinning and execution snapshots by hand
- `BuildRecoveryPlan`, `ApplyRecoveryPlan`, and `Workflows::ManualResume`
  describe orchestration only
- `Workflows::ManualRetry` reuses the paused-work recovery target-resolution
  contract instead of resolving paused compatibility ad hoc
- `Conversations::ValidateAgentDeploymentTarget` no longer carries paused-work
  semantics that belong only to recovery
- the new recovery target owner and rebinding owner each have direct unit tests
- tests cover:
  - plain resume
  - rotated replacement resume
  - manual recovery required on compatibility drift
  - manual recovery required on selector-resolution drift

### Batch 2: Mutation Guard Contract Cleanup

#### Objective

Shrink the live-mutation and timeline-mutation entry surface until the public
 wrappers map cleanly to mutation intent instead of historical namespace
 convenience.

After this batch:

- there is one canonical entry wrapper for conversation entry mutations
- there is one canonical entry wrapper for timeline mutations
- quiescence checks are called directly through the canonical validator instead
  of through a private helper module
- thin alias wrappers are deleted
- retained-state wrappers that still express a distinct contract may remain

#### Target Shape

Keep these as the public mutation contract family:

- `Conversations::WithRetainedStateLock`
- `Conversations::WithRetainedLifecycleLock`
- `Conversations::ValidateMutableState`
- `Conversations::WithMutableStateLock`
- `Conversations::ValidateQuiescence`
- `Workflows::WithMutableWorkflowContext`
- `Turns::WithTimelineMutationLock`
- `Turns::ValidateTimelineMutationTarget`

Delete these thin wrapper concepts:

- `Turns::WithConversationEntryLock`
- `Turns::WithTimelineActionLock`
- `Conversations::WorkQuiescenceGuard`

Move their message shaping into the surviving callers so the callsite says
which contract is being used without adding an extra alias class.

#### Production Files In Scope

- `core_matrix/app/models/conversation_blocker_snapshot.rb`
- `core_matrix/app/services/conversations/validate_mutable_state.rb`
- `core_matrix/app/services/conversations/with_mutable_state_lock.rb`
- `core_matrix/app/services/conversations/with_conversation_entry_lock.rb`
- `core_matrix/app/services/conversations/with_retained_state_lock.rb`
- `core_matrix/app/services/conversations/with_retained_lifecycle_lock.rb`
- `core_matrix/app/services/conversations/validate_quiescence.rb`
- `core_matrix/app/services/workflows/with_mutable_workflow_context.rb`
- `core_matrix/app/services/turns/with_timeline_mutation_lock.rb`
- `core_matrix/app/services/turns/validate_timeline_mutation_target.rb`
- `core_matrix/app/services/turns/start_user_turn.rb`
- `core_matrix/app/services/turns/start_agent_turn.rb`
- `core_matrix/app/services/turns/start_automation_turn.rb`
- `core_matrix/app/services/turns/queue_follow_up.rb`
- `core_matrix/app/services/turns/steer_current_input.rb`
- `core_matrix/app/services/turns/retry_output.rb`
- `core_matrix/app/services/turns/select_output_variant.rb`
- `core_matrix/app/services/turns/edit_tail_input.rb`
- `core_matrix/app/services/turns/rerun_output.rb`
- `core_matrix/app/services/conversations/rollback_to_turn.rb`
- `core_matrix/app/services/conversations/archive.rb`
- `core_matrix/app/services/conversations/finalize_deletion.rb`
- `core_matrix/app/services/conversations/purge_deleted.rb`
- `core_matrix/app/services/conversations/request_close.rb`
- `core_matrix/app/services/publications/publish_live.rb`

#### Files Expected To Be Deleted

- `core_matrix/app/services/turns/with_conversation_entry_lock.rb`
- `core_matrix/app/services/turns/with_timeline_action_lock.rb`
- `core_matrix/app/services/conversations/work_quiescence_guard.rb`

#### Test Files In Scope

- `core_matrix/test/models/conversation_blocker_snapshot_test.rb`
- `core_matrix/test/services/conversations/with_conversation_entry_lock_test.rb`
- `core_matrix/test/services/conversations/with_retained_lifecycle_lock_test.rb`
- `core_matrix/test/services/conversations/validate_quiescence_test.rb`
- `core_matrix/test/services/conversations/finalize_deletion_test.rb`
- `core_matrix/test/services/turns/validate_timeline_mutation_target_test.rb`
- `core_matrix/test/services/workflows/manual_resume_test.rb`
- `core_matrix/test/services/conversations/archive_test.rb`
- `core_matrix/test/services/conversations/purge_deleted_test.rb`
- `core_matrix/test/services/conversations/request_deletion_test.rb`
- `core_matrix/test/services/conversations/rollback_to_turn_test.rb`
- `core_matrix/test/services/publications/publish_live_test.rb`

#### Test Files Expected To Be Added

- `core_matrix/test/services/conversations/validate_mutable_state_test.rb`
- `core_matrix/test/services/conversations/with_mutable_state_lock_test.rb`
- `core_matrix/test/services/conversations/with_retained_state_lock_test.rb`
- `core_matrix/test/services/turns/with_timeline_mutation_lock_test.rb`
- `core_matrix/test/services/conversations/request_close_test.rb`

#### Test Files Expected To Be Deleted

- `core_matrix/test/services/turns/with_conversation_entry_lock_test.rb`
- `core_matrix/test/services/turns/with_timeline_action_lock_test.rb`

#### Behavior Docs To Update

- `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- `core_matrix/docs/behavior/publication-and-live-projection.md`

#### Batch 2 Confirmation List

Before closing Batch 2, confirm all of the following:

- the deleted thin wrappers are gone from both production code and tests
- no production caller still references the deleted wrapper class names
- `ConversationBlockerSnapshot` remains the only blocker-fact owner
- operator summary and enforcement readers still derive from the same blocker
  snapshot family
- the surviving wrapper names each correspond to a distinct mutation intent
  rather than a namespace alias
- each surviving public wrapper has a direct unit test in its own namespace

### Batch 3: Read-Side Query Type Split

#### Objective

Make read-side object names reveal whether they are:

- database queries
- in-memory projections
- cross-source resolvers

After this batch:

- `app/queries` contains only query-shaped objects
- projection builders move out of `app/queries`
- resolver-style read objects move out of `app/queries`
- thin query wrappers over `ConversationBlockerSnapshot` disappear in favor of
  the snapshot's own readers

#### Target Shape

Use this type boundary:

- `app/queries` for database-backed query objects
- `app/projections` for assembly of visible or published read models
- `app/resolvers` for effective-value resolution across multiple sources

Planned read-side reshaping:

- move `ConversationVariables::ResolveQuery` to a resolver
- move `ConversationTranscripts::ListQuery` to a projection
- move `Publications::LiveProjectionQuery` to a projection
- move `Workflows::ProjectionQuery` to a projection
- delete `Conversations::WorkBarrierQuery`
- delete `Conversations::CloseSummaryQuery`
- delete `Conversations::DependencyBlockersQuery`
- update callers to use `ConversationBlockerSnapshot` readers directly

#### Production Files In Scope

- `core_matrix/app/queries/conversation_variables/resolve_query.rb`
- `core_matrix/app/queries/conversation_transcripts/list_query.rb`
- `core_matrix/app/queries/publications/live_projection_query.rb`
- `core_matrix/app/queries/workflows/projection_query.rb`
- `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- `core_matrix/app/queries/conversations/work_barrier_query.rb`
- `core_matrix/app/queries/conversations/close_summary_query.rb`
- `core_matrix/app/queries/conversations/dependency_blockers_query.rb`
- `core_matrix/app/controllers/agent_api/conversation_variables_controller.rb`
- `core_matrix/app/controllers/agent_api/conversation_transcripts_controller.rb`
- `core_matrix/app/services/conversations/validate_quiescence.rb`
- `core_matrix/app/services/conversations/validate_timeline_suffix_supersession.rb`
- `core_matrix/app/services/conversations/purge_deleted.rb`

#### Files Expected To Be Added

- `core_matrix/app/projections/conversation_transcripts/page_projection.rb`
- `core_matrix/app/projections/publications/live_projection.rb`
- `core_matrix/app/projections/workflows/projection.rb`
- `core_matrix/app/resolvers/conversation_variables/visible_values_resolver.rb`

#### Files Expected To Be Deleted

- `core_matrix/app/queries/conversation_variables/resolve_query.rb`
- `core_matrix/app/queries/conversation_transcripts/list_query.rb`
- `core_matrix/app/queries/publications/live_projection_query.rb`
- `core_matrix/app/queries/workflows/projection_query.rb`
- `core_matrix/app/queries/conversations/work_barrier_query.rb`
- `core_matrix/app/queries/conversations/close_summary_query.rb`
- `core_matrix/app/queries/conversations/dependency_blockers_query.rb`

#### Test Files In Scope

- `core_matrix/test/queries/conversations/blocker_snapshot_query_test.rb`
- `core_matrix/test/integration/canonical_variable_flow_test.rb`
- `core_matrix/test/integration/publication_flow_test.rb`
- `core_matrix/test/integration/workflow_yield_materialization_flow_test.rb`

#### Test Files Expected To Be Added

- `core_matrix/test/projections/conversation_transcripts/page_projection_test.rb`
- `core_matrix/test/projections/publications/live_projection_test.rb`
- `core_matrix/test/projections/workflows/projection_test.rb`
- `core_matrix/test/resolvers/conversation_variables/visible_values_resolver_test.rb`

#### Test Files Expected To Be Deleted

- `core_matrix/test/queries/conversation_variables/resolve_query_test.rb`
- `core_matrix/test/queries/conversation_transcripts/list_query_test.rb`
- `core_matrix/test/queries/publications/live_projection_query_test.rb`
- `core_matrix/test/queries/conversations/work_barrier_query_test.rb`
- `core_matrix/test/queries/conversations/close_summary_query_test.rb`
- `core_matrix/test/queries/conversations/dependency_blockers_query_test.rb`

#### Behavior Docs To Update

- `core_matrix/docs/behavior/publication-and-live-projection.md`
- `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- `core_matrix/docs/behavior/canonical-variable-history-and-promotion.md`

#### Batch 3 Confirmation List

Before closing Batch 3, confirm all of the following:

- every remaining class under `app/queries` still looks like a query by name,
  data source, and return shape
- no production code references the deleted `*Query` class names listed above
- projection and resolver tests moved with the renamed classes and directories
- controller and integration surfaces still point at the renamed read-side
  owners
- no thin blocker-summary wrapper survived once callers could use
  `ConversationBlockerSnapshot` readers directly

## Multi-Round Confirmation Checklist

Run this checklist at the end of every batch, not only at the very end:

1. Re-scan production code for the old class names and confirm no live caller
   still uses them.
2. Re-scan tests for the old class names and confirm the test surface has moved
   with the code.
3. Re-read the touched behavior docs and confirm they describe the new owner,
   not the deleted wrapper or deleted writer.
4. Verify the planned touched-file list against the actual diff and explain any
   extra touched file before continuing.
5. Re-run the batch-local tests plus one adjacent integration surface so the
   batch does not look stable only in isolation.

## File-List Completeness Rule

This design is only valid if the implementation plan preserves the following
discipline:

- every batch task must declare the production files, test files, and behavior
  docs it expects to touch
- every batch must declare which files are expected to be deleted
- every batch must end with a grep-based stale-path check
- if implementation reveals a new production caller or test caller outside the
  listed files, update the plan before changing code so the confirmation lists
  stay complete

## Final Acceptance Gate

This three-batch refactor is complete only when all of the following are true:

- recovery and rebind semantics have one obvious owner family
- live mutation and timeline mutation entrypoints no longer depend on duplicate
  alias wrappers
- read-side object names communicate their real type
- the deleted class names no longer appear in production code
- the updated behavior docs describe the new shape as current behavior
- the test suite proves each new owner through direct unit tests plus adjacent
  integration flows
