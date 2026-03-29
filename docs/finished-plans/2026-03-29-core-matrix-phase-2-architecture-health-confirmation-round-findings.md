# Core Matrix Phase 2 Architecture Health Confirmation Round Findings

## Scope

- This is a post-archive confirmation round.
- The archived iterative audit is the baseline.
- The purpose is to confirm whether any additional high-confidence structural issues remain undiscovered.
- The review still includes the `core_matrix <-> agents/fenix` boundary.

## Archived Baseline

The archived iterative audit judged the current `core_matrix` to be governable
but still most exposed at the newer delegation and runtime-contract seams.
Provider request-setting ownership, blocker-summary projection, and
machine-facing capability formatting looked materially improved, while recovery,
runtime capability preservation, subagent close control, and the
`core_matrix <-> agents/fenix` boundary remained the structural pressure points.

- Archived confirmed findings:
  deployment recovery still has duplicate rebinding authority; capability
  preservation checks are narrower than the runtime contract they claim to
  protect; `SubagentSession` close progression is split across two state
  machines; the `core_matrix <-> fenix` execution-context contract drops real
  model hints on the floor.
- Archived risk smells most likely to hide adjacent undiscovered work:
  capability-snapshot reuse rules are duplicated across registration paths;
  Fenix treats `allowed_tool_names` as trace data instead of an execution-time
  constraint; mutable-state and quiescence enforcement still ask callers to know
  too many wrapper families.
- Archived top structural priorities:
  unify runtime capability preservation and reuse rules; collapse
  `SubagentSession` close progression onto one canonical state model; repair the
  `core_matrix <-> fenix` execution-context contract and lock it down with
  cross-project contract tests.

## Confirmation Passes

- [x] Runtime capability preservation and reuse rules
- [x] `SubagentSession` close progression and neighboring close-control readers
- [x] `core_matrix <-> fenix` execution-context contract, including model hints
  and visible-tool semantics
- [x] Wrapper and payload drift around the archived hotspots

### Runtime capability preservation and reuse

- Files reviewed:
  `core_matrix/app/models/agent_deployment.rb`,
  `core_matrix/app/models/capability_snapshot.rb`,
  `core_matrix/app/models/runtime_capability_contract.rb`,
  `core_matrix/app/services/agent_deployments/build_recovery_plan.rb`,
  `core_matrix/app/services/agent_deployments/apply_recovery_plan.rb`,
  `core_matrix/app/services/agent_deployments/validate_recovery_target.rb`,
  `core_matrix/app/services/agent_deployments/handshake.rb`,
  `core_matrix/app/services/agent_deployments/register.rb`,
  `core_matrix/app/services/capability_snapshots/reconcile.rb`,
  `core_matrix/app/services/conversations/validate_agent_deployment_target.rb`,
  `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`,
  `core_matrix/app/services/workflows/manual_resume.rb`,
  `core_matrix/app/services/workflows/manual_retry.rb`,
  `core_matrix/test/services/agent_deployments/build_recovery_plan_test.rb`,
  `core_matrix/test/services/agent_deployments/apply_recovery_plan_test.rb`,
  `core_matrix/test/services/agent_deployments/handshake_test.rb`,
  `core_matrix/test/services/capability_snapshots/reconcile_test.rb`,
  `core_matrix/test/services/conversations/validate_agent_deployment_target_test.rb`,
  `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`,
  `core_matrix/test/services/workflows/manual_resume_test.rb`,
  and `core_matrix/test/requests/agent_api/registrations_test.rb`.
- Result:
  no additional high-confidence issue found beyond the archived
  capability-preservation finding and the archived snapshot-reuse baseline.
  Recovery and manual rebinding both converge on
  `AgentDeployments::ValidateRecoveryTarget` plus the full
  `CapabilitySnapshot#matches_runtime_capability_contract?` comparison, and the
  registration paths still reuse `CapabilitySnapshots::Reconcile` for snapshot
  identity, so this confirmation pass did not surface a separate adjacent
  structural leak.

### `SubagentSession` close progression and adjacent readers

- Files reviewed:
  `core_matrix/app/models/concerns/closable_runtime_resource.rb`,
  `core_matrix/app/models/subagent_session.rb`,
  `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`,
  `core_matrix/app/queries/conversations/close_summary_query.rb`,
  `core_matrix/app/services/agent_control/apply_close_outcome.rb`,
  `core_matrix/app/services/agent_control/closable_resource_routing.rb`,
  `core_matrix/app/services/agent_control/create_resource_close_request.rb`,
  `core_matrix/app/services/agent_control/handle_close_report.rb`,
  `core_matrix/app/services/agent_control/validate_close_report_freshness.rb`,
  `core_matrix/app/services/conversations/progress_close_requests.rb`,
  `core_matrix/app/services/conversations/reconcile_close_operation.rb`,
  `core_matrix/app/services/conversations/request_close.rb`,
  `core_matrix/app/services/conversations/request_turn_interrupt.rb`,
  `core_matrix/app/services/conversations/validate_quiescence.rb`,
  `core_matrix/app/services/subagent_sessions/list_for_conversation.rb`,
  `core_matrix/app/services/subagent_sessions/owned_tree.rb`,
  `core_matrix/app/services/subagent_sessions/request_close.rb`,
  `core_matrix/app/services/subagent_sessions/wait.rb`,
  `core_matrix/test/models/subagent_session_test.rb`,
  `core_matrix/test/queries/conversations/blocker_snapshot_query_test.rb`,
  `core_matrix/test/queries/conversations/close_summary_query_test.rb`,
  `core_matrix/test/services/agent_control/report_test.rb`,
  `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`,
  `core_matrix/test/services/conversations/validate_quiescence_test.rb`,
  and `core_matrix/test/services/subagent_sessions/request_close_test.rb`.
- Result:
  no additional high-confidence issue found beyond the archived
  `SubagentSession` split-state-machine finding. The adjacent readers and
  close-control helpers still compensate by consulting `close_state` and
  `last_known_status`, but in the current code those checks reinforce the
  already-archived split-authority problem instead of exposing a second,
  separate owner or reader contract failure.

### `core_matrix <-> fenix` execution-context boundary

- Files reviewed:
  `core_matrix/app/services/agent_control/create_execution_assignment.rb`,
  `core_matrix/app/services/provider_execution/build_request_context.rb`,
  `core_matrix/app/services/workflows/build_execution_snapshot.rb`,
  `core_matrix/app/services/workflows/create_for_turn.rb`,
  `core_matrix/app/services/workflows/step_retry.rb`,
  `contracts/core_matrix_fenix_execution_assignment_v1.json`,
  `core_matrix/test/services/agent_control/create_execution_assignment_test.rb`,
  `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`,
  `core_matrix/test/services/workflows/create_for_turn_test.rb`,
  `core_matrix/test/services/workflows/step_retry_test.rb`,
  `agents/fenix/app/services/fenix/context/build_execution_context.rb`,
  `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`,
  `agents/fenix/app/services/fenix/hooks/review_tool_call.rb`,
  `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`,
  `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`,
  `agents/fenix/test/integration/runtime_flow_test.rb`,
  `agents/fenix/test/services/fenix/hooks/runtime_hooks_test.rb`,
  `agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`,
  and `agents/fenix/README.md`.
- Result:
  one additional high-confidence boundary issue exists. The normal
  create-for-turn path and the shared contract fixture now agree on model hints
  and visible-tool semantics, and `Fenix::Hooks::ReviewToolCall` does consume
  `allowed_tool_names` as a real policy input. The remaining adjacent leak is
  the retry assignment family, which bypasses the frozen execution-snapshot
  envelope.

### Adjacent anti-pattern sweep

- Search patterns used:
  in `core_matrix`, `profile_catalog|tool_catalog|allowed_tool_names|close_requested|close_state|recovery_plan|capability_snapshot|default_config_snapshot|conversation_override_schema_snapshot`
  and `with_lock|transaction|close_operation|request_close|apply_close_outcome`;
  in `agents/fenix`,
  `allowed_tool_names|likely_model|model_context|agent_context|profile`.
- Result:
  the sweep did not surface a second new high-confidence structural issue. It
  reinforced the archived capability-preservation and `SubagentSession`
  hotspots, confirmed that current Fenix runtime code now treats
  `allowed_tool_names` as an execution-time constraint, and re-confirmed that
  the only newly promoted issue in this round is the retry-assignment drift
  away from the frozen execution-snapshot contract.

## New High-Confidence Findings

### Step-retry assignments bypass the frozen execution-snapshot contract

- Why it matters:
  `Workflows::CreateForTurn` builds assignments with `context_messages`,
  `budget_hints`, `provider_execution`, and `model_context` from the turn's
  frozen execution snapshot, but `Workflows::StepRetry` requeues work by
  passing only task-payload data into `AgentControl::CreateExecutionAssignment`.
  That means a real Core Matrix retry path can send Fenix an execution
  assignment without the frozen model and budget context that the boundary now
  claims to preserve.
- Evidence:
  `core_matrix/app/services/workflows/create_for_turn.rb`,
  `core_matrix/app/services/workflows/step_retry.rb`,
  `core_matrix/app/services/agent_control/create_execution_assignment.rb`,
  `core_matrix/test/services/workflows/create_for_turn_test.rb`,
  `core_matrix/test/services/workflows/step_retry_test.rb`,
  `contracts/core_matrix_fenix_execution_assignment_v1.json`,
  `agents/fenix/app/services/fenix/context/build_execution_context.rb`, and
  `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`.
- Structural impact:
  the `core_matrix <-> fenix` execution contract is still inconsistent across
  assignment families. Initial and subagent executions carry a rich frozen
  envelope, while retry-generated executions silently degrade to task payload
  plus agent context. Any model-sensitive compaction, budgeting, or future
  provider-backed retry behavior therefore cannot trust the mailbox payload
  shape across real execution paths.
- Action direction:
  make execution assignments derive the frozen execution-context envelope from
  one shared source such as `agent_task_run.turn.execution_snapshot` for every
  assignment family, then add cross-project contract coverage for a real
  step-retry assignment payload instead of only the create-for-turn fixture.

## No-New-Finding Judgment

This confirmation round did find one additional high-confidence structural
issue: retry-generated execution assignments do not preserve the frozen
execution-snapshot envelope that the normal `core_matrix <-> fenix` boundary
now expects. The archived iterative audit therefore remains the baseline, but
it should not yet be treated as exhaustive.

Post-fix narrow recheck:
after `fix: preserve execution snapshot on retry assignments` (`661afb5`), the
specific boundary leak identified in this round no longer reproduces in current
code. `AgentControl::CreateExecutionAssignment` now derives the frozen
execution-context envelope from `turn.execution_snapshot` across assignment
families, and `Workflows::StepRetry` now passes a standard `task_payload`
wrapper instead of bypassing the contract.

## Completeness Check

- The archived iterative findings and the archived iterative plan were re-read
  before looking for anything new.
- All three targeted confirmation passes ran:
  runtime capability preservation and reuse, `SubagentSession` close
  progression and adjacent readers, and the `core_matrix <-> fenix`
  execution-context boundary.
- One adjacent anti-pattern sweep ran across neighboring wrapper and payload
  families in `core_matrix` and `agents/fenix`.
- This report explicitly states that one new high-confidence finding exists, so
  the result is not `no new high-confidence findings`.
- Post-fix narrow recheck ran on the repaired boundary and re-verified:
  `core_matrix/test/services/workflows/step_retry_test.rb`,
  `core_matrix/test/services/agent_control/create_execution_assignment_test.rb`,
  `core_matrix/test/services/workflows/create_for_turn_test.rb`,
  `agents/fenix/test/integration/runtime_flow_test.rb`, and
  `agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`.
