#!/usr/bin/env ruby

require_relative "../lib/boot"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
delivery_mode = ENV.fetch("FENIX_DELIVERY_MODE", "realtime")

ManualAcceptanceSupport.reset_backend_state!
bootstrap = ManualAcceptanceSupport.bootstrap_and_seed!
external = ManualAcceptanceSupport.create_external_agent_program!(
  installation: bootstrap.installation,
  actor: bootstrap.user,
  key: "fenix-external",
  display_name: "External Fenix"
)
registration = ManualAcceptanceSupport.register_external_runtime!(
  enrollment_token: external.fetch(:enrollment_token),
  runtime_base_url: runtime_base_url,
  executor_fingerprint: "acceptance-external-fenix-environment",
  fingerprint: "acceptance-external-fenix-v1"
)
run = ManualAcceptanceSupport.run_fenix_mailbox_task!(
  agent_program_version: registration.fetch(:agent_program_version),
  machine_credential: registration.fetch(:machine_credential),
  executor_machine_credential: registration.fetch(:executor_machine_credential),
  runtime_base_url: runtime_base_url,
  content: "External Fenix deterministic tool turn",
  mode: "deterministic_tool",
  extra_payload: { "expression" => "7 + 5" },
  delivery_mode: delivery_mode
)

expected_dag_shape = ["agent_turn_step"]
observed_dag_shape = ManualAcceptanceSupport.workflow_node_keys(run.fetch(:workflow_run))
expected_conversation_state = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "completed",
  "workflow_wait_state" => "ready",
  "turn_lifecycle_state" => "active",
  "agent_task_run_state" => "completed",
}
observed_conversation_state = ManualAcceptanceSupport.workflow_state_hash(
  conversation: run.fetch(:conversation),
  workflow_run: run.fetch(:workflow_run),
  turn: run.fetch(:turn),
  agent_task_run: run.fetch(:agent_task_run)
)

ManualAcceptanceSupport.write_json(
  ManualAcceptanceSupport.scenario_result(
    scenario: "external_fenix_validation",
    expected_dag_shape: expected_dag_shape,
    observed_dag_shape: observed_dag_shape,
    expected_conversation_state: expected_conversation_state,
    observed_conversation_state: observed_conversation_state,
    extra: {
      "agent_program_version_id" => registration.fetch(:agent_program_version).public_id,
      "delivery_mode" => delivery_mode,
      "executor_program_id" => registration.fetch(:executor_program)&.public_id,
      "agent_session_id" => registration.fetch(:registration).fetch("agent_session_id"),
      "executor_session_id" => registration.fetch(:registration)["executor_session_id"],
      "heartbeat_lifecycle_state" => registration.fetch(:heartbeat).fetch("lifecycle_state"),
      "heartbeat_health_status" => registration.fetch(:heartbeat).fetch("health_status"),
      "conversation_id" => run.fetch(:conversation).public_id,
      "turn_id" => run.fetch(:turn).public_id,
      "workflow_run_id" => run.fetch(:workflow_run).public_id,
      "agent_task_run_id" => run.fetch(:agent_task_run).public_id,
      "runtime_execution_status" => run.fetch(:execution).fetch("status"),
      "runtime_output" => run.fetch(:execution).fetch("output"),
      "report_results" => run.fetch(:report_results),
    }
  )
)
