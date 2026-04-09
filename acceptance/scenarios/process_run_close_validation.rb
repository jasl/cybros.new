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
  executor_fingerprint: "acceptance-process-run-environment",
  fingerprint: fingerprint
)

result = nil

ManualAcceptanceSupport.with_fenix_control_worker_for_registration!(
  registration: bundled,
  realtime_timeout_seconds: delivery_mode == "realtime" ? 5 : 0
) do
  result = begin
    conversation_context = ManualAcceptanceSupport.create_conversation!(deployment: bundled.deployment)
    run = ManualAcceptanceSupport.start_turn_workflow_on_conversation!(
      conversation: conversation_context.fetch(:conversation),
      deployment: bundled.deployment,
      content: "Start a long-running background service and then close it gracefully.",
      root_node_key: "turn_step",
      root_node_type: "turn_step",
      decision_source: "system"
    )
    workflow_node = run.fetch(:workflow_run).workflow_nodes.find_by!(node_key: "turn_step")
    round_bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    tool_result = ManualAcceptanceSupport.execute_program_tool_call!(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "acceptance-process-exec-1",
        "tool_name" => "process_exec",
        "arguments" => {
          "kind" => "background_service",
          "command_line" => "trap 'exit 0' TERM; while :; do sleep 1; done",
        },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      agent_program_version: bundled.deployment
    )
    process_run = ProcessRun.find_by_public_id!(tool_result.result.fetch("process_run_id"))
    ManualAcceptanceSupport.wait_for_process_run_state!(process_run: process_run, lifecycle_states: "running")

    run.merge(
      conversation: conversation_context.fetch(:conversation).reload,
      workflow_node: workflow_node,
      process_run: process_run.reload,
      tool_invocation: tool_result.tool_invocation.reload,
      execution: {
        "status" => tool_result.tool_invocation.reload.status,
        "output" => tool_result.result,
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

expected_dag_shape = ["turn_step"]
observed_dag_shape = ManualAcceptanceSupport.workflow_node_keys(workflow_run)
expected_conversation_state = {
  "conversation_state" => "active",
  "process_lifecycle_state" => "stopped",
  "process_close_state" => "closed",
  "process_close_outcome_kind" => "graceful",
}
observed_conversation_state = ManualAcceptanceSupport.workflow_state_hash(
  conversation: result.fetch(:conversation),
  workflow_run: workflow_run,
  turn: turn,
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
      "deployment_id" => bundled.deployment.public_id,
      "delivery_mode" => delivery_mode,
      "executor_program_id" => bundled.executor_program.public_id,
      "conversation_id" => result.fetch(:conversation).public_id,
      "turn_id" => turn.public_id,
      "workflow_run_id" => workflow_run.public_id,
      "workflow_node_id" => result.fetch(:workflow_node).public_id,
      "process_run_id" => process_run.public_id,
      "close_request_id" => close_request&.public_id,
      "tool_invocation_id" => result.fetch(:tool_invocation).public_id,
      "tool_invocation_status" => result.fetch(:tool_invocation).status,
      "provider_handle" => model_context["provider_handle"],
      "model_ref" => model_context["model_ref"],
      "api_model" => model_context["api_model"],
      "selector" => workflow_run.normalized_selector,
      "process_lifecycle_state" => process_run.lifecycle_state,
      "process_close_state" => process_run.close_state,
      "process_close_outcome_kind" => process_run.close_outcome_kind,
      "runtime_execution_status" => result.fetch(:execution).fetch("status"),
      "runtime_output" => result.fetch(:execution)["output"],
      "workflow_node_event_states" => WorkflowNodeEvent.where(workflow_node: result.fetch(:workflow_node)).order(:ordinal).pluck(Arel.sql("payload ->> 'state'")),
    }
  )
)
