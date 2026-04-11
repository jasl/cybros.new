#!/usr/bin/env ruby

require_relative "../lib/boot"

agent_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
runtime_base_url = ENV.fetch("NEXUS_RUNTIME_BASE_URL", "http://127.0.0.1:3301")

Acceptance::ManualSupport.reset_backend_state!
bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!
external = Acceptance::ManualSupport.create_external_agent!(
  installation: bootstrap.installation,
  actor: bootstrap.user,
  key: "fenix-external",
  display_name: "External Fenix"
)
registration = Acceptance::ManualSupport.register_external_runtime!(
  enrollment_token: external.fetch(:enrollment_token),
  runtime_base_url: runtime_base_url,
  agent_base_url: agent_base_url,
  execution_runtime_fingerprint: "acceptance-external-fenix-environment",
  fingerprint: "acceptance-external-fenix-v1"
)
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
    conversation_context = Acceptance::ManualSupport.create_conversation!(agent_snapshot: registration.agent_snapshot)
    run = Acceptance::ManualSupport.start_turn_workflow_on_conversation!(
      conversation: conversation_context.fetch(:conversation),
      execution_runtime: registration.execution_runtime,
      content: "External Fenix deterministic tool turn",
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

expected_dag_shape = ["agent_turn_step"]
observed_dag_shape = Acceptance::ManualSupport.workflow_node_keys(run.fetch(:workflow_run))
expected_conversation_state = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "completed",
  "workflow_wait_state" => "ready",
  "turn_lifecycle_state" => "active",
  "agent_task_run_state" => "completed",
}
observed_conversation_state = Acceptance::ManualSupport.workflow_state_hash(
  conversation: conversation_context.fetch(:conversation),
  workflow_run: run.fetch(:workflow_run),
  turn: run.fetch(:turn),
  agent_task_run: run.fetch(:agent_task_run)
)

Acceptance::ManualSupport.write_json(
  Acceptance::ManualSupport.scenario_result(
    scenario: "external_fenix_validation",
    expected_dag_shape: expected_dag_shape,
    observed_dag_shape: observed_dag_shape,
    expected_conversation_state: expected_conversation_state,
    observed_conversation_state: observed_conversation_state,
    extra: {
      "agent_snapshot_id" => registration.agent_snapshot.public_id,
      "execution_runtime_id" => registration.execution_runtime&.public_id,
      "agent_connection_id" => registration.agent_connection_id,
      "execution_runtime_connection_id" => registration.execution_runtime_connection_id,
      "heartbeat_lifecycle_state" => registration.heartbeat.fetch("lifecycle_state"),
      "heartbeat_health_status" => registration.heartbeat.fetch("health_status"),
      "agent_base_url" => agent_base_url,
      "runtime_base_url" => runtime_base_url,
      "conversation_id" => conversation_context.fetch(:conversation).public_id,
      "turn_id" => run.fetch(:turn).public_id,
      "workflow_run_id" => run.fetch(:workflow_run).public_id,
      "agent_task_run_id" => run.fetch(:agent_task_run).public_id,
      "runtime_execution_status" => run.fetch(:execution).fetch("status"),
      "runtime_output" => run.fetch(:execution).fetch("output"),
      "report_results" => run.fetch(:report_results),
    }
  )
)
