#!/usr/bin/env ruby

require_relative "../lib/boot"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
delivery_mode = ENV.fetch("FENIX_DELIVERY_MODE", "realtime")
fingerprint = "acceptance-process-run-runtime"

ManualAcceptanceSupport.reset_backend_state!
bootstrap = ManualAcceptanceSupport.bootstrap_and_seed!
bundled = ManualAcceptanceSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  runtime_fingerprint: "acceptance-process-run-environment",
  fingerprint: fingerprint,
  sdk_version: "fenix-0.1.0"
)

result = nil
close_loop = { "items" => [] }

ManualAcceptanceSupport.with_fenix_control_worker!(
  machine_credential: bundled.fetch(:machine_credential),
  realtime_timeout_seconds: delivery_mode == "realtime" ? 5 : 0
) do
  result ||= begin
    conversation_context = ManualAcceptanceSupport.create_conversation!(deployment: bundled.fetch(:runtime).deployment)
    run = ManualAcceptanceSupport.start_turn_workflow_on_conversation!(
      conversation: conversation_context.fetch(:conversation),
      deployment: bundled.fetch(:runtime).deployment,
      content: "Start a long-running background service and then close it gracefully.",
      root_node_key: "agent_turn_step",
      root_node_type: "turn_step",
      decision_source: "agent_program",
      initial_kind: "turn_step",
      initial_payload: {
        "mode" => "deterministic_tool",
        "tool_name" => "process_exec",
        "command_line" => "trap 'exit 0' TERM; while :; do sleep 1; done",
      }
    )
    agent_task_run = ManualAcceptanceSupport.wait_for_agent_task_terminal!(agent_task_run: run.fetch(:agent_task_run))
    process_run = ManualAcceptanceSupport.wait_for_process_run!(workflow_node: agent_task_run.workflow_node)
    ManualAcceptanceSupport.wait_for_process_run_state!(process_run: process_run, lifecycle_states: "running")

    run.merge(
      conversation: conversation_context.fetch(:conversation).reload,
      agent_task_run: agent_task_run,
      process_run: process_run.reload,
      report_results: ManualAcceptanceSupport.report_results_for(agent_task_run: agent_task_run),
      execution: {
        "status" => "completed",
        "output" => agent_task_run.terminal_payload["output"],
      }
    )
  end

  process_run = result.fetch(:process_run).reload
  occurred_at = Time.current
  close_request = AgentControl::CreateResourceCloseRequest.call(
    resource: process_run,
    request_kind: "manual_validation_close",
    reason_kind: "operator_stop",
    strictness: "graceful",
    grace_deadline_at: occurred_at + 30.seconds,
    force_deadline_at: occurred_at + 60.seconds,
    protocol_message_id: "acceptance-process-run-close"
  )

  ManualAcceptanceSupport.wait_for_process_run_state!(
    process_run: process_run,
    lifecycle_states: "stopped",
    close_states: "closed",
    timeout_seconds: 15
  )

  result[:close_request] = close_request.reload
end

turn = result.fetch(:turn).reload
workflow_run = result.fetch(:workflow_run).reload
model_context = workflow_run.execution_snapshot.model_context
process_run = result.fetch(:process_run).reload
close_request = result.fetch(:close_request)

expected_dag_shape = ["agent_turn_step"]
observed_dag_shape = ManualAcceptanceSupport.workflow_node_keys(workflow_run)
expected_conversation_state = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "completed",
  "workflow_wait_state" => "ready",
  "turn_lifecycle_state" => "active",
  "agent_task_run_state" => "completed",
  "process_lifecycle_state" => "stopped",
  "process_close_state" => "closed",
  "process_close_outcome_kind" => "graceful",
}
observed_conversation_state = ManualAcceptanceSupport.workflow_state_hash(
  conversation: result.fetch(:conversation),
  workflow_run: workflow_run,
  turn: turn,
  agent_task_run: result.fetch(:agent_task_run),
  extra: {
    "process_lifecycle_state" => process_run.reload.lifecycle_state,
    "process_close_state" => process_run.close_state,
    "process_close_outcome_kind" => process_run.close_outcome_kind,
    "close_request_status" => close_request&.reload&.status,
  }
)

ManualAcceptanceSupport.write_json(
  ManualAcceptanceSupport.scenario_result(
    scenario: "process_run_close_validation",
    expected_dag_shape: expected_dag_shape,
    observed_dag_shape: observed_dag_shape,
    expected_conversation_state: expected_conversation_state,
    observed_conversation_state: observed_conversation_state,
    extra: {
      "deployment_id" => bundled.fetch(:runtime).deployment.public_id,
      "delivery_mode" => delivery_mode,
      "execution_runtime_id" => bundled.fetch(:runtime).execution_runtime.public_id,
      "conversation_id" => result.fetch(:conversation).public_id,
      "turn_id" => turn.public_id,
      "workflow_run_id" => workflow_run.public_id,
      "agent_task_run_id" => result.fetch(:agent_task_run).public_id,
      "process_run_id" => process_run.public_id,
      "close_request_id" => close_request&.public_id,
      "provider_handle" => model_context["provider_handle"],
      "model_ref" => model_context["model_ref"],
      "api_model" => model_context["api_model"],
      "selector" => workflow_run.normalized_selector,
      "process_lifecycle_state" => process_run.lifecycle_state,
      "process_close_state" => process_run.close_state,
      "process_close_outcome_kind" => process_run.close_outcome_kind,
      "runtime_execution_status" => result.fetch(:execution).fetch("status"),
      "runtime_output" => result.fetch(:execution)["output"],
      "close_loop_items" => close_loop.fetch("items").map { |item| item.slice("kind", "mailbox_item_id", "status") },
      "report_results" => result.fetch(:report_results),
      "workflow_node_event_states" => WorkflowNodeEvent.where(workflow_node: result.fetch(:agent_task_run).workflow_node).order(:ordinal).pluck(Arel.sql("payload ->> 'state'")),
    }
  )
)
