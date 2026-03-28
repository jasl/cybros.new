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
- [ ] `core_matrix <-> fenix` execution-context contract, including model hints
  and visible-tool semantics
- [ ] Wrapper and payload drift around the archived hotspots

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

## New High-Confidence Findings

## No-New-Finding Judgment

## Completeness Check
