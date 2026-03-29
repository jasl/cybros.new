# Core Matrix Boundary Coverage Working Ledger

## Baseline

- Date: `2026-03-29`
- App code files: `266`
- Test files: `267`
- Latest full-suite verification at ledger creation:
  - `736 runs, 3745 assertions, 0 failures, 0 errors, 0 skips`
- Latest SimpleCov line result at ledger creation:
  - `50.37%` (`7528 / 14945`)

## Status Legend

- `pending_scan`
- `done`
- `needs_tests`
- `needs_bugfix`
- `keep_watch`

## Wave Summary

### Wave 1: Write-Side State Machines

- Status: `in_progress`
- Scope:
  - `app/services/workflows/**/*`
  - `app/services/turns/**/*`
  - `app/services/conversations/**/*`
  - `app/services/provider_execution/**/*`
  - `app/services/agent_deployments/**/*`
- Actions Taken:
  - seeded inventory
- Remaining Gaps:
  - full scan
  - boundary branch classification

### Wave 2: Control Plane And Recovery

- Status: `pending`
- Scope:
  - `app/services/agent_control/**/*`
  - `app/services/subagent_sessions/**/*`
  - `app/services/installations/**/*`
  - `app/services/execution_environments/**/*`
  - `app/services/leases/**/*`
  - `app/services/processes/**/*`
- Actions Taken:
  - none yet
- Remaining Gaps:
  - full scan
  - boundary branch classification

### Wave 3: Read Side And External Contracts

- Status: `pending`
- Scope:
  - `app/controllers/agent_api/**/*`
  - `app/queries/**/*`
  - `app/projections/**/*`
  - `app/resolvers/**/*`
- Actions Taken:
  - none yet
- Remaining Gaps:
  - full scan
  - boundary branch classification

### Wave 4: Models And Extreme Constraints

- Status: `pending`
- Scope:
  - `app/models/**/*`
  - `app/models/concerns/**/*`
  - leftover channels, jobs, helpers, and lower-risk controllers
- Actions Taken:
  - none yet
- Remaining Gaps:
  - full scan
  - boundary branch classification

## Inventory

### app/channels

- pending_scan | app/channels/agent_control_channel.rb

### app/channels/application_cable

- pending_scan | app/channels/application_cable/channel.rb
- pending_scan | app/channels/application_cable/connection.rb

### app/controllers/agent_api

- pending_scan | app/controllers/agent_api/base_controller.rb
- pending_scan | app/controllers/agent_api/capabilities_controller.rb
- pending_scan | app/controllers/agent_api/control_controller.rb
- pending_scan | app/controllers/agent_api/conversation_transcripts_controller.rb
- pending_scan | app/controllers/agent_api/conversation_variables_controller.rb
- pending_scan | app/controllers/agent_api/health_controller.rb
- pending_scan | app/controllers/agent_api/heartbeats_controller.rb
- pending_scan | app/controllers/agent_api/human_interactions_controller.rb
- pending_scan | app/controllers/agent_api/registrations_controller.rb
- pending_scan | app/controllers/agent_api/workspace_variables_controller.rb

### app/controllers

- pending_scan | app/controllers/application_controller.rb
- pending_scan | app/controllers/home_controller.rb

### app/controllers/mock_llm/v1

- pending_scan | app/controllers/mock_llm/v1/application_controller.rb
- pending_scan | app/controllers/mock_llm/v1/chat_completions_controller.rb
- pending_scan | app/controllers/mock_llm/v1/models_controller.rb

### app/helpers

- pending_scan | app/helpers/application_helper.rb

### app/jobs

- pending_scan | app/jobs/application_job.rb

### app/jobs/lineage_stores

- pending_scan | app/jobs/lineage_stores/garbage_collect_job.rb

### app/mailers

- pending_scan | app/mailers/application_mailer.rb

### app/models

- pending_scan | app/models/agent_control_mailbox_item.rb
- pending_scan | app/models/agent_control_report_receipt.rb
- pending_scan | app/models/agent_deployment.rb
- pending_scan | app/models/agent_deployment_recovery_plan.rb
- pending_scan | app/models/agent_deployment_recovery_target.rb
- pending_scan | app/models/agent_enrollment.rb
- pending_scan | app/models/agent_installation.rb
- pending_scan | app/models/agent_message.rb
- pending_scan | app/models/agent_task_run.rb
- pending_scan | app/models/application_record.rb
- pending_scan | app/models/approval_request.rb
- pending_scan | app/models/audit_log.rb
- pending_scan | app/models/canonical_variable.rb
- pending_scan | app/models/capability_snapshot.rb
- pending_scan | app/models/conversation.rb
- pending_scan | app/models/conversation_blocker_snapshot.rb
- pending_scan | app/models/conversation_close_operation.rb
- pending_scan | app/models/conversation_closure.rb
- pending_scan | app/models/conversation_event.rb
- pending_scan | app/models/conversation_import.rb
- pending_scan | app/models/conversation_message_visibility.rb
- pending_scan | app/models/conversation_summary_segment.rb
- pending_scan | app/models/execution_environment.rb
- pending_scan | app/models/execution_lease.rb
- pending_scan | app/models/execution_profile_fact.rb
- pending_scan | app/models/human_form_request.rb
- pending_scan | app/models/human_interaction_request.rb
- pending_scan | app/models/human_task_request.rb
- pending_scan | app/models/identity.rb
- pending_scan | app/models/installation.rb
- pending_scan | app/models/invitation.rb
- pending_scan | app/models/lineage_store.rb
- pending_scan | app/models/lineage_store_entry.rb
- pending_scan | app/models/lineage_store_reference.rb
- pending_scan | app/models/lineage_store_snapshot.rb
- pending_scan | app/models/lineage_store_value.rb
- pending_scan | app/models/message.rb
- pending_scan | app/models/message_attachment.rb
- pending_scan | app/models/process_run.rb
- pending_scan | app/models/provider_credential.rb
- pending_scan | app/models/provider_entitlement.rb
- pending_scan | app/models/provider_policy.rb
- pending_scan | app/models/provider_request_context.rb
- pending_scan | app/models/provider_request_settings_schema.rb
- pending_scan | app/models/publication.rb
- pending_scan | app/models/publication_access_event.rb
- pending_scan | app/models/runtime_capability_contract.rb
- pending_scan | app/models/session.rb
- pending_scan | app/models/subagent_session.rb
- pending_scan | app/models/turn.rb
- pending_scan | app/models/turn_execution_snapshot.rb
- pending_scan | app/models/usage_event.rb
- pending_scan | app/models/usage_rollup.rb
- pending_scan | app/models/user.rb
- pending_scan | app/models/user_agent_binding.rb
- pending_scan | app/models/user_message.rb
- pending_scan | app/models/workflow_artifact.rb
- pending_scan | app/models/workflow_edge.rb
- pending_scan | app/models/workflow_node.rb
- pending_scan | app/models/workflow_node_event.rb
- pending_scan | app/models/workflow_run.rb
- pending_scan | app/models/workflow_wait_snapshot.rb
- pending_scan | app/models/workspace.rb

### app/models/concerns

- pending_scan | app/models/concerns/closable_runtime_resource.rb
- pending_scan | app/models/concerns/has_public_id.rb

### app/projections/conversation_transcripts

- pending_scan | app/projections/conversation_transcripts/page_projection.rb

### app/projections/publications

- pending_scan | app/projections/publications/live_projection.rb

### app/projections/workflows

- pending_scan | app/projections/workflows/projection.rb

### app/queries/agent_installations

- pending_scan | app/queries/agent_installations/visible_to_user_query.rb

### app/queries/conversations

- pending_scan | app/queries/conversations/blocker_snapshot_query.rb

### app/queries/execution_profiling

- pending_scan | app/queries/execution_profiling/summary_query.rb

### app/queries/human_interactions

- pending_scan | app/queries/human_interactions/open_for_user_query.rb

### app/queries/lineage_stores

- pending_scan | app/queries/lineage_stores/get_query.rb
- pending_scan | app/queries/lineage_stores/key_metadata.rb
- pending_scan | app/queries/lineage_stores/key_page.rb
- pending_scan | app/queries/lineage_stores/list_keys_query.rb
- pending_scan | app/queries/lineage_stores/multi_get_query.rb
- pending_scan | app/queries/lineage_stores/query_support.rb
- pending_scan | app/queries/lineage_stores/visible_value.rb

### app/queries/provider_usage

- pending_scan | app/queries/provider_usage/window_usage_query.rb

### app/queries/workspace_variables

- pending_scan | app/queries/workspace_variables/get_query.rb
- pending_scan | app/queries/workspace_variables/list_query.rb
- pending_scan | app/queries/workspace_variables/mget_query.rb

### app/queries/workspaces

- pending_scan | app/queries/workspaces/for_user_query.rb

### app/resolvers/conversation_variables

- pending_scan | app/resolvers/conversation_variables/visible_values_resolver.rb

### app/services/agent_control

- pending_scan | app/services/agent_control/apply_close_outcome.rb
- pending_scan | app/services/agent_control/closable_resource_registry.rb
- pending_scan | app/services/agent_control/closable_resource_routing.rb
- pending_scan | app/services/agent_control/create_execution_assignment.rb
- pending_scan | app/services/agent_control/create_resource_close_request.rb
- pending_scan | app/services/agent_control/handle_close_report.rb
- pending_scan | app/services/agent_control/handle_execution_report.rb
- pending_scan | app/services/agent_control/handle_health_report.rb
- pending_scan | app/services/agent_control/lease_mailbox_item.rb
- pending_scan | app/services/agent_control/poll.rb
- pending_scan | app/services/agent_control/progress_close_request.rb
- pending_scan | app/services/agent_control/publish_pending.rb
- pending_scan | app/services/agent_control/report.rb
- pending_scan | app/services/agent_control/report_dispatch.rb
- pending_scan | app/services/agent_control/resolve_target_runtime.rb
- pending_scan | app/services/agent_control/serialize_mailbox_item.rb
- pending_scan | app/services/agent_control/stream_name.rb
- pending_scan | app/services/agent_control/touch_deployment_activity.rb
- pending_scan | app/services/agent_control/validate_close_report_freshness.rb
- pending_scan | app/services/agent_control/validate_execution_report_freshness.rb

### app/services/agent_control/realtime_links

- pending_scan | app/services/agent_control/realtime_links/close.rb
- pending_scan | app/services/agent_control/realtime_links/open.rb

### app/services/agent_deployments

- pending_scan | app/services/agent_deployments/apply_recovery_plan.rb
- pending_scan | app/services/agent_deployments/auto_resume_workflows.rb
- pending_scan | app/services/agent_deployments/bootstrap.rb
- pending_scan | app/services/agent_deployments/build_recovery_plan.rb
- pending_scan | app/services/agent_deployments/handshake.rb
- pending_scan | app/services/agent_deployments/mark_unavailable.rb
- pending_scan | app/services/agent_deployments/rebind_turn.rb
- pending_scan | app/services/agent_deployments/reconcile_config.rb
- pending_scan | app/services/agent_deployments/record_heartbeat.rb
- pending_scan | app/services/agent_deployments/register.rb
- pending_scan | app/services/agent_deployments/resolve_recovery_target.rb
- pending_scan | app/services/agent_deployments/retire.rb
- pending_scan | app/services/agent_deployments/revoke_machine_credential.rb
- pending_scan | app/services/agent_deployments/rotate_machine_credential.rb
- pending_scan | app/services/agent_deployments/unavailable_pause_state.rb

### app/services/agent_enrollments

- pending_scan | app/services/agent_enrollments/issue.rb

### app/services/attachments

- pending_scan | app/services/attachments/materialize_refs.rb

### app/services/capability_snapshots

- pending_scan | app/services/capability_snapshots/reconcile.rb

### app/services/conversation_events

- pending_scan | app/services/conversation_events/project.rb

### app/services/conversation_summaries

- pending_scan | app/services/conversation_summaries/create_segment.rb

### app/services/conversations

- pending_scan | app/services/conversations/add_import.rb
- pending_scan | app/services/conversations/archive.rb
- pending_scan | app/services/conversations/context_projection.rb
- pending_scan | app/services/conversations/create_automation_root.rb
- pending_scan | app/services/conversations/create_branch.rb
- pending_scan | app/services/conversations/create_checkpoint.rb
- pending_scan | app/services/conversations/create_fork.rb
- pending_scan | app/services/conversations/create_root.rb
- pending_scan | app/services/conversations/creation_support.rb
- pending_scan | app/services/conversations/finalize_deletion.rb
- pending_scan | app/services/conversations/historical_anchor_projection.rb
- pending_scan | app/services/conversations/progress_close_requests.rb
- pending_scan | app/services/conversations/purge_deleted.rb
- pending_scan | app/services/conversations/purge_plan.rb
- pending_scan | app/services/conversations/reconcile_close_operation.rb
- pending_scan | app/services/conversations/refresh_runtime_contract.rb
- pending_scan | app/services/conversations/request_close.rb
- pending_scan | app/services/conversations/request_deletion.rb
- pending_scan | app/services/conversations/request_resource_closes.rb
- pending_scan | app/services/conversations/request_turn_interrupt.rb
- pending_scan | app/services/conversations/rollback_to_turn.rb
- pending_scan | app/services/conversations/switch_agent_deployment.rb
- pending_scan | app/services/conversations/transcript_projection.rb
- pending_scan | app/services/conversations/unarchive.rb
- pending_scan | app/services/conversations/update_override.rb
- pending_scan | app/services/conversations/validate_agent_deployment_target.rb
- pending_scan | app/services/conversations/validate_historical_anchor.rb
- pending_scan | app/services/conversations/validate_mutable_state.rb
- pending_scan | app/services/conversations/validate_quiescence.rb
- pending_scan | app/services/conversations/validate_retained_state.rb
- pending_scan | app/services/conversations/validate_timeline_suffix_supersession.rb
- pending_scan | app/services/conversations/with_conversation_entry_lock.rb
- pending_scan | app/services/conversations/with_mutable_state_lock.rb
- pending_scan | app/services/conversations/with_retained_lifecycle_lock.rb
- pending_scan | app/services/conversations/with_retained_state_lock.rb

### app/services/execution_environments

- pending_scan | app/services/execution_environments/reconcile.rb
- pending_scan | app/services/execution_environments/record_capabilities.rb
- pending_scan | app/services/execution_environments/resolve_delivery_endpoint.rb

### app/services/execution_profiling

- pending_scan | app/services/execution_profiling/record_fact.rb

### app/services/human_interactions

- pending_scan | app/services/human_interactions/complete_task.rb
- pending_scan | app/services/human_interactions/request.rb
- pending_scan | app/services/human_interactions/resolve_approval.rb
- pending_scan | app/services/human_interactions/submit_form.rb
- pending_scan | app/services/human_interactions/with_mutable_request_context.rb

### app/services/installations

- pending_scan | app/services/installations/bootstrap_bundled_agent_binding.rb
- pending_scan | app/services/installations/bootstrap_first_admin.rb
- pending_scan | app/services/installations/register_bundled_agent_runtime.rb

### app/services/invitations

- pending_scan | app/services/invitations/consume.rb

### app/services/leases

- pending_scan | app/services/leases/acquire.rb
- pending_scan | app/services/leases/heartbeat.rb
- pending_scan | app/services/leases/release.rb

### app/services/lineage_stores

- pending_scan | app/services/lineage_stores/bootstrap_for_conversation.rb
- pending_scan | app/services/lineage_stores/compact_snapshot.rb
- pending_scan | app/services/lineage_stores/delete_key.rb
- pending_scan | app/services/lineage_stores/garbage_collect.rb
- pending_scan | app/services/lineage_stores/set.rb
- pending_scan | app/services/lineage_stores/write_support.rb

### app/services/messages

- pending_scan | app/services/messages/update_visibility.rb

### app/services/processes

- pending_scan | app/services/processes/start.rb
- pending_scan | app/services/processes/stop.rb

### app/services/provider_catalog

- pending_scan | app/services/provider_catalog/load.rb
- pending_scan | app/services/provider_catalog/validate.rb

### app/services/provider_credentials

- pending_scan | app/services/provider_credentials/upsert_secret.rb

### app/services/provider_entitlements

- pending_scan | app/services/provider_entitlements/upsert.rb

### app/services/provider_execution

- pending_scan | app/services/provider_execution/build_request_context.rb
- pending_scan | app/services/provider_execution/dispatch_request.rb
- pending_scan | app/services/provider_execution/execute_turn_step.rb
- pending_scan | app/services/provider_execution/persist_turn_step_failure.rb
- pending_scan | app/services/provider_execution/persist_turn_step_success.rb
- pending_scan | app/services/provider_execution/with_fresh_execution_state_lock.rb

### app/services/provider_policies

- pending_scan | app/services/provider_policies/upsert.rb

### app/services/provider_usage

- pending_scan | app/services/provider_usage/project_rollups.rb
- pending_scan | app/services/provider_usage/record_event.rb

### app/services/providers

- pending_scan | app/services/providers/check_availability.rb

### app/services/publications

- pending_scan | app/services/publications/publish_live.rb
- pending_scan | app/services/publications/record_access.rb
- pending_scan | app/services/publications/revoke.rb

### app/services/runtime_capabilities

- pending_scan | app/services/runtime_capabilities/compose_effective_tool_catalog.rb
- pending_scan | app/services/runtime_capabilities/compose_for_conversation.rb

### app/services/subagent_sessions

- pending_scan | app/services/subagent_sessions/list_for_conversation.rb
- pending_scan | app/services/subagent_sessions/owned_tree.rb
- pending_scan | app/services/subagent_sessions/request_close.rb
- pending_scan | app/services/subagent_sessions/send_message.rb
- pending_scan | app/services/subagent_sessions/spawn.rb
- pending_scan | app/services/subagent_sessions/validate_addressability.rb
- pending_scan | app/services/subagent_sessions/wait.rb

### app/services/turns

- pending_scan | app/services/turns/create_output_variant.rb
- pending_scan | app/services/turns/edit_tail_input.rb
- pending_scan | app/services/turns/queue_follow_up.rb
- pending_scan | app/services/turns/rerun_output.rb
- pending_scan | app/services/turns/retry_output.rb
- pending_scan | app/services/turns/select_output_variant.rb
- pending_scan | app/services/turns/start_agent_turn.rb
- pending_scan | app/services/turns/start_automation_turn.rb
- pending_scan | app/services/turns/start_user_turn.rb
- pending_scan | app/services/turns/steer_current_input.rb
- pending_scan | app/services/turns/validate_timeline_mutation_target.rb
- pending_scan | app/services/turns/with_timeline_mutation_lock.rb

### app/services/user_agent_bindings

- pending_scan | app/services/user_agent_bindings/enable.rb

### app/services/users

- pending_scan | app/services/users/grant_admin.rb
- pending_scan | app/services/users/revoke_admin.rb

### app/services/variables

- pending_scan | app/services/variables/promote_to_workspace.rb
- pending_scan | app/services/variables/write.rb

### app/services/workflows

- pending_scan | app/services/workflows/build_execution_snapshot.rb
- pending_scan | app/services/workflows/create_for_turn.rb
- pending_scan | app/services/workflows/execute_run.rb
- pending_scan | app/services/workflows/intent_batch_materialization.rb
- pending_scan | app/services/workflows/manual_resume.rb
- pending_scan | app/services/workflows/manual_retry.rb
- pending_scan | app/services/workflows/mutate.rb
- pending_scan | app/services/workflows/resolve_model_selector.rb
- pending_scan | app/services/workflows/scheduler.rb
- pending_scan | app/services/workflows/step_retry.rb
- pending_scan | app/services/workflows/wait_state.rb
- pending_scan | app/services/workflows/with_locked_workflow_context.rb
- pending_scan | app/services/workflows/with_mutable_workflow_context.rb

### app/services/workspaces

- pending_scan | app/services/workspaces/create_default.rb
