#!/usr/bin/env ruby

require_relative "../lib/boot"

agent_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
runtime_base_url = ENV.fetch("NEXUS_RUNTIME_BASE_URL", "http://127.0.0.1:3301")

Acceptance::ManualSupport.reset_backend_state!
bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!
bundled_registration = Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: agent_base_url,
  execution_runtime_fingerprint: "acceptance-bundled-fenix-environment",
  fingerprint: "acceptance-bundled-fenix-runtime"
)
pairing_session = PairingSessions::Issue.call(
  agent: bundled_registration.agent_definition_version.agent,
  actor: bootstrap.user,
  expires_at: 2.hours.from_now
)
bring_your_own_runtime_registration = Acceptance::ManualSupport.register_bring_your_own_execution_runtime!(
  pairing_token: pairing_session.plaintext_token,
  runtime_base_url: runtime_base_url,
  execution_runtime_fingerprint: "acceptance-bring-your-own-runtime-environment"
)
conversation_context = nil
run = nil

Acceptance::ManualSupport.with_fenix_control_worker!(
  agent_connection_credential: bundled_registration.agent_connection_credential,
  execution_runtime_connection_credential: bring_your_own_runtime_registration.fetch(:execution_runtime_connection_credential),
  limit: 1,
  inline: true
) do
  Acceptance::ManualSupport.with_nexus_control_worker!(
    execution_runtime_connection_credential: bring_your_own_runtime_registration.fetch(:execution_runtime_connection_credential),
    limit: 1,
    inline: true
  ) do
    conversation_context = Acceptance::ManualSupport.create_conversation!(
      agent_definition_version: bundled_registration.agent_definition_version
    )
    run = Acceptance::ManualSupport.start_turn_workflow_on_conversation!(
      conversation: conversation_context.fetch(:conversation),
      execution_runtime: bring_your_own_runtime_registration.fetch(:execution_runtime),
      content: "Bring your own execution runtime deterministic tool turn",
      root_node_key: "agent_turn_step",
      root_node_type: "turn_step",
      decision_source: "agent",
      initial_kind: "turn_step",
      initial_payload: { "mode" => "deterministic_tool", "expression" => "8 * 8" }
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
      turn: run.fetch(:turn).reload,
      workflow_run: run.fetch(:workflow_run).reload,
      agent_task_run: agent_task_run.reload,
      execution: {
        "status" => agent_task_run.lifecycle_state == "completed" ? "completed" : "failed",
        "output" => execution_output,
        "error" => agent_task_run.lifecycle_state == "completed" ? nil : terminal_payload
      }
    )
  end
end

bundled_agent = bundled_registration.agent_definition_version.agent.reload
selected_turn = run.fetch(:turn).reload
selected_runtime = bring_your_own_runtime_registration.fetch(:execution_runtime)
selected_runtime_version = bring_your_own_runtime_registration.fetch(:execution_runtime_version)

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
  turn: selected_turn,
  agent_task_run: run.fetch(:agent_task_run)
)

Acceptance::ManualSupport.write_json(
  Acceptance::ManualSupport.scenario_result(
    scenario: "bring_your_own_execution_runtime_validation",
    expected_dag_shape: expected_dag_shape,
    observed_dag_shape: observed_dag_shape,
    expected_conversation_state: expected_conversation_state,
    observed_conversation_state: observed_conversation_state,
    extra: {
      "pairing_session_id" => pairing_session.public_id,
      "agent_definition_version_id" => bundled_registration.agent_definition_version.public_id,
      "agent_connection_id" => bundled_registration.agent_connection_id,
      "bundled_execution_runtime_id" => bundled_registration.execution_runtime.public_id,
      "registered_execution_runtime_id" => selected_runtime.public_id,
      "registered_execution_runtime_version_id" => selected_runtime_version.public_id,
      "selected_turn_execution_runtime_id" => selected_turn.execution_runtime.public_id,
      "selected_turn_execution_runtime_version_id" => selected_turn.execution_runtime_version.public_id,
      "default_execution_runtime_id" => bundled_agent.default_execution_runtime&.public_id,
      "reused_logical_runtime" => bundled_registration.execution_runtime.public_id == selected_runtime.public_id,
      "agent_base_url" => agent_base_url,
      "runtime_base_url" => runtime_base_url,
      "conversation_id" => conversation_context.fetch(:conversation).public_id,
      "turn_id" => selected_turn.public_id,
      "workflow_run_id" => run.fetch(:workflow_run).public_id,
      "agent_task_run_id" => run.fetch(:agent_task_run).public_id,
      "runtime_execution_status" => run.fetch(:execution).fetch("status"),
      "runtime_output" => run.fetch(:execution).fetch("output"),
    }
  )
)
