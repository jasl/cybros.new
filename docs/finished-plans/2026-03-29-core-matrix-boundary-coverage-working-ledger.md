# Core Matrix Boundary Coverage Working Ledger

## Baseline

- Date: `2026-03-29`
- App code files: `286`
- Test files: `311`
- Latest full-suite verification:
  - `792 runs, 3977 assertions, 0 failures, 0 errors, 0 skips`
- Latest SimpleCov line result:
  - `50.45%` (`7543 / 14951`)

## Status Legend

- `done`: directly strengthened this campaign or verified as adequately covered by existing direct/request/integration tests
- `keep_watch`: scanned and judged low-risk or already indirectly covered, but still worth revisiting if adjacent behavior changes

## Wave Summary

### Wave 1: Write-Side State Machines

- Status: `completed`
- Scope:
  - `app/services/workflows/**/*`
  - `app/services/turns/**/*`
  - `app/services/conversations/**/*`
  - `app/services/provider_execution/**/*`
  - `app/services/agent_deployments/**/*`
  - `app/services/lineage_stores/**/*`
- Actions Taken:
  - added direct coverage for previously untested state helpers, projections, and write helpers
  - fixed `Turns::CreateOutputVariant` to start output variant indexes at `0`
  - normalized `AgentDeployments::UnavailablePauseState.resume_attributes` to return symbol-keyed top-level wait attributes
  - added overflow write/delete compaction tests that prove `LineageStores::WriteSupport` preserves the latest visible chain across depth-32 rollover
- Remaining Gaps:
  - no current blocker in the write-support path; remaining lineage gaps are read-side scale cases, not write continuity

### Wave 2: Control Plane And Recovery

- Status: `completed`
- Scope:
  - `app/services/agent_control/**/*`
  - `app/services/subagent_sessions/**/*`
  - `app/services/installations/**/*`
  - `app/services/execution_environments/**/*`
  - `app/services/leases/**/*`
  - `app/services/processes/**/*`
- Actions Taken:
  - added direct coverage for freshness validators, runtime routing, close-request creation, close-outcome application, health updates, and addressability guards
  - added direct stale-wrapper coverage for `HandleExecutionReport` heartbeat timeout and `HandleCloseReport` expired mailbox leases
  - verified control-plane directories as a group with `61 runs, 309 assertions, 0 failures, 0 errors, 0 skips`
- Remaining Gaps:
  - `lease_mailbox_item`, `progress_close_request`, and low-level realtime/open helpers remain `keep_watch` because they are still primarily exercised through `poll` and integration flows

### Wave 3: Read Side And External Contracts

- Status: `completed`
- Scope:
  - `app/controllers/agent_api/**/*`
  - `app/controllers/mock_llm/**/*`
  - `app/queries/**/*`
  - `app/projections/**/*`
  - `app/resolvers/**/*`
- Actions Taken:
  - verified request/query/projection/resolver suites together with `56 runs, 377 assertions, 0 failures, 0 errors, 0 skips`
  - added request coverage for malformed `registrations` and `capabilities` payload permutations so invalid runtime contracts return `422` instead of surfacing transport-level errors
  - kept base controllers and struct-like lineage-store query objects on `keep_watch` because public contracts are already enforced one layer up
- Remaining Gaps:
  - malformed payload coverage is now in place for the highest-risk agent capability endpoints; remaining read-side gaps are lower-risk empty/filter permutations on passive endpoints

### Wave 4: Models And Extreme Constraints

- Status: `completed`
- Scope:
  - `app/models/**/*`
  - `app/models/concerns/**/*`
  - low-risk bases and wrappers outside the main service waves
- Actions Taken:
  - added direct tests for `AgentControlReportReceipt` and `TurnExecutionSnapshot`
  - verified that remaining model concerns are already exercised through concrete model tests
- Remaining Gaps:
  - `ApplicationRecord` and abstract concerns remain `keep_watch` because they intentionally carry little standalone behavior

## Inventory

### app/channels

- keep_watch | app/channels/agent_control_channel.rb

### app/channels/application_cable

- keep_watch | app/channels/application_cable/channel.rb
- keep_watch | app/channels/application_cable/connection.rb

### app/controllers/agent_api

- keep_watch | app/controllers/agent_api/base_controller.rb
- done | app/controllers/agent_api/capabilities_controller.rb
- keep_watch | app/controllers/agent_api/control_controller.rb
- keep_watch | app/controllers/agent_api/conversation_transcripts_controller.rb
- keep_watch | app/controllers/agent_api/conversation_variables_controller.rb
- keep_watch | app/controllers/agent_api/health_controller.rb
- keep_watch | app/controllers/agent_api/heartbeats_controller.rb
- keep_watch | app/controllers/agent_api/human_interactions_controller.rb
- done | app/controllers/agent_api/registrations_controller.rb
- keep_watch | app/controllers/agent_api/workspace_variables_controller.rb

### app/controllers

- keep_watch | app/controllers/application_controller.rb
- keep_watch | app/controllers/home_controller.rb

### app/controllers/mock_llm/v1

- keep_watch | app/controllers/mock_llm/v1/application_controller.rb
- keep_watch | app/controllers/mock_llm/v1/chat_completions_controller.rb
- keep_watch | app/controllers/mock_llm/v1/models_controller.rb

### app/helpers

- keep_watch | app/helpers/application_helper.rb

### app/jobs

- keep_watch | app/jobs/application_job.rb

### app/jobs/lineage_stores

- keep_watch | app/jobs/lineage_stores/garbage_collect_job.rb

### app/mailers

- keep_watch | app/mailers/application_mailer.rb

### app/models

- done | app/models/agent_control_mailbox_item.rb
- done | app/models/agent_control_report_receipt.rb
- done | app/models/agent_deployment.rb
- done | app/models/agent_deployment_recovery_plan.rb
- done | app/models/agent_deployment_recovery_target.rb
- done | app/models/agent_enrollment.rb
- done | app/models/agent_installation.rb
- done | app/models/agent_message.rb
- done | app/models/agent_task_run.rb
- keep_watch | app/models/application_record.rb
- done | app/models/approval_request.rb
- done | app/models/audit_log.rb
- done | app/models/canonical_variable.rb
- done | app/models/capability_snapshot.rb
- done | app/models/conversation.rb
- done | app/models/conversation_blocker_snapshot.rb
- done | app/models/conversation_close_operation.rb
- done | app/models/conversation_closure.rb
- done | app/models/conversation_event.rb
- done | app/models/conversation_import.rb
- done | app/models/conversation_message_visibility.rb
- done | app/models/conversation_summary_segment.rb
- done | app/models/execution_environment.rb
- done | app/models/execution_lease.rb
- done | app/models/execution_profile_fact.rb
- done | app/models/human_form_request.rb
- done | app/models/human_interaction_request.rb
- done | app/models/human_task_request.rb
- done | app/models/identity.rb
- done | app/models/installation.rb
- done | app/models/invitation.rb
- done | app/models/lineage_store.rb
- done | app/models/lineage_store_entry.rb
- done | app/models/lineage_store_reference.rb
- done | app/models/lineage_store_snapshot.rb
- done | app/models/lineage_store_value.rb
- done | app/models/message.rb
- done | app/models/message_attachment.rb
- done | app/models/process_run.rb
- done | app/models/provider_credential.rb
- done | app/models/provider_entitlement.rb
- done | app/models/provider_policy.rb
- done | app/models/provider_request_context.rb
- done | app/models/provider_request_settings_schema.rb
- done | app/models/publication.rb
- done | app/models/publication_access_event.rb
- done | app/models/runtime_capability_contract.rb
- done | app/models/session.rb
- done | app/models/subagent_session.rb
- done | app/models/turn.rb
- done | app/models/turn_execution_snapshot.rb
- done | app/models/usage_event.rb
- done | app/models/usage_rollup.rb
- done | app/models/user.rb
- done | app/models/user_agent_binding.rb
- done | app/models/user_message.rb
- done | app/models/workflow_artifact.rb
- done | app/models/workflow_edge.rb
- done | app/models/workflow_node.rb
- done | app/models/workflow_node_event.rb
- done | app/models/workflow_run.rb
- done | app/models/workflow_wait_snapshot.rb
- done | app/models/workspace.rb

### app/models/concerns

- keep_watch | app/models/concerns/closable_runtime_resource.rb
- done | app/models/concerns/has_public_id.rb

### app/projections/conversation_transcripts

- done | app/projections/conversation_transcripts/page_projection.rb

### app/projections/publications

- done | app/projections/publications/live_projection.rb

### app/projections/workflows

- done | app/projections/workflows/projection.rb

### app/queries/agent_installations

- done | app/queries/agent_installations/visible_to_user_query.rb

### app/queries/conversations

- done | app/queries/conversations/blocker_snapshot_query.rb

### app/queries/execution_profiling

- done | app/queries/execution_profiling/summary_query.rb

### app/queries/human_interactions

- done | app/queries/human_interactions/open_for_user_query.rb

### app/queries/lineage_stores

- done | app/queries/lineage_stores/get_query.rb
- keep_watch | app/queries/lineage_stores/key_metadata.rb
- keep_watch | app/queries/lineage_stores/key_page.rb
- done | app/queries/lineage_stores/list_keys_query.rb
- done | app/queries/lineage_stores/multi_get_query.rb
- keep_watch | app/queries/lineage_stores/query_support.rb
- keep_watch | app/queries/lineage_stores/visible_value.rb

### app/queries/provider_usage

- done | app/queries/provider_usage/window_usage_query.rb

### app/queries/workspace_variables

- done | app/queries/workspace_variables/get_query.rb
- done | app/queries/workspace_variables/list_query.rb
- done | app/queries/workspace_variables/mget_query.rb

### app/queries/workspaces

- done | app/queries/workspaces/for_user_query.rb

### app/resolvers/conversation_variables

- done | app/resolvers/conversation_variables/visible_values_resolver.rb

### app/services/agent_control

- done | app/services/agent_control/apply_close_outcome.rb
- done | app/services/agent_control/closable_resource_registry.rb
- done | app/services/agent_control/closable_resource_routing.rb
- done | app/services/agent_control/create_execution_assignment.rb
- done | app/services/agent_control/create_resource_close_request.rb
- done | app/services/agent_control/handle_close_report.rb
- done | app/services/agent_control/handle_execution_report.rb
- done | app/services/agent_control/handle_health_report.rb
- keep_watch | app/services/agent_control/lease_mailbox_item.rb
- done | app/services/agent_control/poll.rb
- keep_watch | app/services/agent_control/progress_close_request.rb
- done | app/services/agent_control/publish_pending.rb
- done | app/services/agent_control/report.rb
- done | app/services/agent_control/report_dispatch.rb
- done | app/services/agent_control/resolve_target_runtime.rb
- done | app/services/agent_control/serialize_mailbox_item.rb
- done | app/services/agent_control/stream_name.rb
- done | app/services/agent_control/touch_deployment_activity.rb
- done | app/services/agent_control/validate_close_report_freshness.rb
- done | app/services/agent_control/validate_execution_report_freshness.rb

### app/services/agent_control/realtime_links

- done | app/services/agent_control/realtime_links/close.rb
- keep_watch | app/services/agent_control/realtime_links/open.rb

### app/services/agent_deployments

- done | app/services/agent_deployments/apply_recovery_plan.rb
- done | app/services/agent_deployments/auto_resume_workflows.rb
- done | app/services/agent_deployments/bootstrap.rb
- done | app/services/agent_deployments/build_recovery_plan.rb
- done | app/services/agent_deployments/handshake.rb
- done | app/services/agent_deployments/mark_unavailable.rb
- done | app/services/agent_deployments/rebind_turn.rb
- done | app/services/agent_deployments/reconcile_config.rb
- done | app/services/agent_deployments/record_heartbeat.rb
- done | app/services/agent_deployments/register.rb
- done | app/services/agent_deployments/resolve_recovery_target.rb
- done | app/services/agent_deployments/retire.rb
- done | app/services/agent_deployments/revoke_machine_credential.rb
- done | app/services/agent_deployments/rotate_machine_credential.rb
- done | app/services/agent_deployments/unavailable_pause_state.rb

### app/services/agent_enrollments

- done | app/services/agent_enrollments/issue.rb

### app/services/attachments

- done | app/services/attachments/materialize_refs.rb

### app/services/capability_snapshots

- done | app/services/capability_snapshots/reconcile.rb

### app/services/conversation_events

- done | app/services/conversation_events/project.rb

### app/services/conversation_summaries

- done | app/services/conversation_summaries/create_segment.rb

### app/services/conversations

- done | app/services/conversations/add_import.rb
- done | app/services/conversations/archive.rb
- done | app/services/conversations/context_projection.rb
- done | app/services/conversations/create_automation_root.rb
- done | app/services/conversations/create_branch.rb
- done | app/services/conversations/create_checkpoint.rb
- done | app/services/conversations/create_fork.rb
- done | app/services/conversations/create_root.rb
- done | app/services/conversations/creation_support.rb
- done | app/services/conversations/finalize_deletion.rb
- done | app/services/conversations/historical_anchor_projection.rb
- done | app/services/conversations/progress_close_requests.rb
- done | app/services/conversations/purge_deleted.rb
- done | app/services/conversations/purge_plan.rb
- done | app/services/conversations/reconcile_close_operation.rb
- done | app/services/conversations/refresh_runtime_contract.rb
- done | app/services/conversations/request_close.rb
- done | app/services/conversations/request_deletion.rb
- done | app/services/conversations/request_resource_closes.rb
- done | app/services/conversations/request_turn_interrupt.rb
- done | app/services/conversations/rollback_to_turn.rb
- done | app/services/conversations/switch_agent_deployment.rb
- done | app/services/conversations/transcript_projection.rb
- done | app/services/conversations/unarchive.rb
- done | app/services/conversations/update_override.rb
- done | app/services/conversations/validate_agent_deployment_target.rb
- done | app/services/conversations/validate_historical_anchor.rb
- done | app/services/conversations/validate_mutable_state.rb
- done | app/services/conversations/validate_quiescence.rb
- done | app/services/conversations/validate_retained_state.rb
- done | app/services/conversations/validate_timeline_suffix_supersession.rb
- done | app/services/conversations/with_conversation_entry_lock.rb
- done | app/services/conversations/with_mutable_state_lock.rb
- done | app/services/conversations/with_retained_lifecycle_lock.rb
- done | app/services/conversations/with_retained_state_lock.rb

### app/services/execution_environments

- done | app/services/execution_environments/reconcile.rb
- done | app/services/execution_environments/record_capabilities.rb
- done | app/services/execution_environments/resolve_delivery_endpoint.rb

### app/services/execution_profiling

- done | app/services/execution_profiling/record_fact.rb

### app/services/human_interactions

- done | app/services/human_interactions/complete_task.rb
- done | app/services/human_interactions/request.rb
- done | app/services/human_interactions/resolve_approval.rb
- done | app/services/human_interactions/submit_form.rb
- done | app/services/human_interactions/with_mutable_request_context.rb

### app/services/installations

- done | app/services/installations/bootstrap_bundled_agent_binding.rb
- done | app/services/installations/bootstrap_first_admin.rb
- done | app/services/installations/register_bundled_agent_runtime.rb

### app/services/invitations

- done | app/services/invitations/consume.rb

### app/services/leases

- done | app/services/leases/acquire.rb
- done | app/services/leases/heartbeat.rb
- done | app/services/leases/release.rb

### app/services/lineage_stores

- done | app/services/lineage_stores/bootstrap_for_conversation.rb
- done | app/services/lineage_stores/compact_snapshot.rb
- done | app/services/lineage_stores/delete_key.rb
- done | app/services/lineage_stores/garbage_collect.rb
- done | app/services/lineage_stores/set.rb
- done | app/services/lineage_stores/write_support.rb

### app/services/messages

- done | app/services/messages/update_visibility.rb

### app/services/processes

- done | app/services/processes/start.rb
- done | app/services/processes/stop.rb

### app/services/provider_catalog

- done | app/services/provider_catalog/load.rb
- done | app/services/provider_catalog/validate.rb

### app/services/provider_credentials

- done | app/services/provider_credentials/upsert_secret.rb

### app/services/provider_entitlements

- done | app/services/provider_entitlements/upsert.rb

### app/services/provider_execution

- done | app/services/provider_execution/build_request_context.rb
- done | app/services/provider_execution/dispatch_request.rb
- done | app/services/provider_execution/execute_turn_step.rb
- done | app/services/provider_execution/persist_turn_step_failure.rb
- done | app/services/provider_execution/persist_turn_step_success.rb
- done | app/services/provider_execution/with_fresh_execution_state_lock.rb

### app/services/provider_policies

- done | app/services/provider_policies/upsert.rb

### app/services/provider_usage

- done | app/services/provider_usage/project_rollups.rb
- done | app/services/provider_usage/record_event.rb

### app/services/providers

- done | app/services/providers/check_availability.rb

### app/services/publications

- done | app/services/publications/publish_live.rb
- done | app/services/publications/record_access.rb
- done | app/services/publications/revoke.rb

### app/services/runtime_capabilities

- done | app/services/runtime_capabilities/compose_effective_tool_catalog.rb
- done | app/services/runtime_capabilities/compose_for_conversation.rb

### app/services/subagent_sessions

- keep_watch | app/services/subagent_sessions/list_for_conversation.rb
- keep_watch | app/services/subagent_sessions/owned_tree.rb
- done | app/services/subagent_sessions/request_close.rb
- done | app/services/subagent_sessions/send_message.rb
- done | app/services/subagent_sessions/spawn.rb
- done | app/services/subagent_sessions/validate_addressability.rb
- done | app/services/subagent_sessions/wait.rb

### app/services/turns

- done | app/services/turns/create_output_variant.rb
- done | app/services/turns/edit_tail_input.rb
- done | app/services/turns/queue_follow_up.rb
- done | app/services/turns/rerun_output.rb
- done | app/services/turns/retry_output.rb
- done | app/services/turns/select_output_variant.rb
- done | app/services/turns/start_agent_turn.rb
- done | app/services/turns/start_automation_turn.rb
- done | app/services/turns/start_user_turn.rb
- done | app/services/turns/steer_current_input.rb
- done | app/services/turns/validate_timeline_mutation_target.rb
- done | app/services/turns/with_timeline_mutation_lock.rb

### app/services/user_agent_bindings

- done | app/services/user_agent_bindings/enable.rb

### app/services/users

- done | app/services/users/grant_admin.rb
- done | app/services/users/revoke_admin.rb

### app/services/variables

- done | app/services/variables/promote_to_workspace.rb
- done | app/services/variables/write.rb

### app/services/workflows

- done | app/services/workflows/build_execution_snapshot.rb
- done | app/services/workflows/create_for_turn.rb
- done | app/services/workflows/execute_run.rb
- done | app/services/workflows/intent_batch_materialization.rb
- done | app/services/workflows/manual_resume.rb
- done | app/services/workflows/manual_retry.rb
- done | app/services/workflows/mutate.rb
- done | app/services/workflows/resolve_model_selector.rb
- done | app/services/workflows/scheduler.rb
- done | app/services/workflows/step_retry.rb
- done | app/services/workflows/wait_state.rb
- done | app/services/workflows/with_locked_workflow_context.rb
- done | app/services/workflows/with_mutable_workflow_context.rb

### app/services/workspaces

- done | app/services/workspaces/create_default.rb
