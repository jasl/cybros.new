#!/usr/bin/env ruby
# ACCEPTANCE_MODE: hybrid_app_api
# This scenario must use app_api where a product/operator surface exists and only keep internal hooks for deterministic mailbox execution.

require_relative "../lib/boot"

agent_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
runtime_base_url = ENV.fetch("NEXUS_RUNTIME_BASE_URL", "http://127.0.0.1:3301")
artifact_stamp = ENV.fetch("BRING_YOUR_OWN_AGENT_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-bring-your-own-agent-validation"
end
artifact_dir = AcceptanceHarness.repo_root.join("acceptance", "artifacts", artifact_stamp)
debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")

Acceptance::ManualSupport.reset_backend_state!
bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!
app_api_session_token = Acceptance::ManualSupport.issue_app_api_session_token!(user: bootstrap.user)
bring_your_own_agent = Acceptance::ManualSupport.app_api_admin_create_onboarding_session!(
  target_kind: "agent",
  agent_key: "bring-your-own-agent",
  display_name: "Bring Your Own Agent",
  session_token: app_api_session_token
)
registration = Acceptance::ManualSupport.register_bring_your_own_runtime!(
  onboarding_token: bring_your_own_agent.fetch("onboarding_token"),
  runtime_base_url: runtime_base_url,
  agent_base_url: agent_base_url,
  execution_runtime_fingerprint: "acceptance-bring-your-own-agent-environment"
)
FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)
conversation_context = nil
run = nil

Acceptance::ManualSupport.with_fenix_control_worker!(
  agent_connection_credential: registration.agent_connection_credential,
  limit: 1,
  inline: true
) do
  Acceptance::ManualSupport.with_nexus_control_worker_for_registration!(
    registration: registration,
    limit: 1,
    inline: true
  ) do
    conversation_context = Acceptance::ManualSupport.create_conversation!(
      agent_definition_version: registration.agent_definition_version
    )
    run = Acceptance::ManualSupport.start_turn_workflow_on_conversation!(
      conversation: conversation_context.fetch(:conversation),
      execution_runtime: registration.execution_runtime,
      content: "Bring your own agent deterministic tool turn",
      root_node_key: "agent_turn_step",
      root_node_type: "turn_step",
      decision_source: "agent",
      initial_kind: "turn_step",
      initial_payload: { "mode" => "deterministic_tool", "expression" => "7 + 5" }
    )
    agent_task_run = Acceptance::ManualSupport.wait_for_agent_task_terminal!(
      agent_task_run: run.fetch(:agent_task_run),
      timeout_seconds: 30
    )
    terminal_payload = agent_task_run.terminal_payload || {}
    execution_output =
      if agent_task_run.lifecycle_state == "completed"
        terminal_payload["output"].presence || terminal_payload.except("terminal_method_id")
      end

    run = run.merge(
      conversation: conversation_context.fetch(:conversation).reload,
      agent_task_run: agent_task_run.reload,
      execution: {
        "status" => agent_task_run.lifecycle_state == "completed" ? "completed" : "failed",
        "output" => execution_output,
        "error" => agent_task_run.lifecycle_state == "completed" ? nil : terminal_payload
      },
      report_results: Acceptance::ManualSupport.report_results_for(agent_task_run:)
    )
  end
end

conversation_id = conversation_context.fetch(:conversation).public_id
turn_id = run.fetch(:turn).public_id
diagnostics = Acceptance::ManualSupport.app_api_conversation_diagnostics_show!(
  conversation_id: conversation_id,
  session_token: app_api_session_token
)
turns_payload = Acceptance::ManualSupport.app_api_conversation_diagnostics_turns!(
  conversation_id: conversation_id,
  session_token: app_api_session_token
)
materialized_diagnostics = Acceptance::ManualSupport.wait_for_app_api_conversation_diagnostics_materialized!(
  conversation_id: conversation_id,
  session_token: app_api_session_token
)
debug_export_download = Acceptance::ManualSupport.app_api_debug_export_conversation!(
  conversation_id: conversation_id,
  session_token: app_api_session_token,
  destination_path: debug_export_path
)
debug_payload = Acceptance::ManualSupport.extract_debug_export_payload!(
  debug_export_download.dig("download", "path")
)
workflow_run = debug_payload.fetch("workflow_runs")
  .select { |candidate| candidate.fetch("turn_id") == turn_id }
  .max_by { |candidate| [candidate.fetch("created_at").to_s, candidate.fetch("workflow_run_id")] } || {}
materialized_turn_snapshot = materialized_diagnostics.fetch("turns").fetch("items")
  .find { |item| item.fetch("turn_id") == turn_id }

expected_dag_shape = ["agent_turn_step"]
observed_dag_shape = debug_payload.fetch("workflow_nodes")
  .select { |node| node.fetch("turn_id") == turn_id }
  .sort_by { |node| [node.fetch("ordinal"), node.fetch("created_at").to_s] }
  .map { |node| node.fetch("node_key") }
expected_conversation_state = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "completed",
  "workflow_wait_state" => "ready",
  "turn_lifecycle_state" => "active",
  "agent_task_run_state" => "completed",
}
observed_conversation_state = Acceptance::ManualSupport.workflow_state_hash(
  conversation: run.fetch(:conversation),
  workflow_run: run.fetch(:workflow_run),
  turn: run.fetch(:turn),
  agent_task_run: run.fetch(:agent_task_run)
)
diagnostics_contract_passed =
  %w[pending ready stale].include?(diagnostics.fetch("diagnostics_status")) &&
  %w[pending ready stale].include?(turns_payload.fetch("diagnostics_status")) &&
  %w[ready stale].include?(materialized_diagnostics.dig("conversation", "diagnostics_status")) &&
  %w[ready stale].include?(materialized_diagnostics.dig("turns", "diagnostics_status")) &&
  materialized_diagnostics.dig("conversation", "snapshot", "lifecycle_state") == expected_conversation_state["conversation_state"] &&
  materialized_turn_snapshot.present? &&
  materialized_turn_snapshot.fetch("lifecycle_state") == expected_conversation_state["turn_lifecycle_state"]

result = Acceptance::ManualSupport.scenario_result(
    scenario: "bring_your_own_agent_validation",
    expected_dag_shape: expected_dag_shape,
    observed_dag_shape: observed_dag_shape,
    expected_conversation_state: expected_conversation_state,
    observed_conversation_state: observed_conversation_state,
    extra: {
      "onboarding_session_id" => bring_your_own_agent.dig("onboarding_session", "onboarding_session_id"),
      "agent_definition_version_id" => registration.agent_definition_version.public_id,
      "execution_runtime_id" => registration.execution_runtime&.public_id,
      "agent_connection_id" => registration.agent_connection_id,
      "execution_runtime_connection_id" => registration.execution_runtime_connection_id,
      "heartbeat_lifecycle_state" => registration.heartbeat.fetch("lifecycle_state"),
      "heartbeat_health_status" => registration.heartbeat.fetch("health_status"),
      "agent_base_url" => agent_base_url,
      "runtime_base_url" => runtime_base_url,
      "conversation_id" => conversation_id,
      "turn_id" => turn_id,
      "workflow_run_id" => workflow_run.fetch("workflow_run_id", nil),
      "agent_task_run_id" => run.fetch(:agent_task_run).public_id,
      "runtime_execution_status" => run.fetch(:execution).fetch("status"),
      "runtime_output" => run.fetch(:execution).fetch("output"),
      "report_results" => run.fetch(:report_results),
      "diagnostics_initial_status" => diagnostics.fetch("diagnostics_status"),
      "diagnostics_turns_initial_status" => turns_payload.fetch("diagnostics_status"),
      "diagnostics_eventual_status" => materialized_diagnostics.dig("conversation", "diagnostics_status"),
      "diagnostics_turns_eventual_status" => materialized_diagnostics.dig("turns", "diagnostics_status"),
      "diagnostics_projection_contract_passed" => diagnostics_contract_passed,
      "debug_export_path" => debug_export_path.to_s,
    }
  )
result["passed"] &&= diagnostics_contract_passed

Acceptance::ManualSupport.write_json(result)
