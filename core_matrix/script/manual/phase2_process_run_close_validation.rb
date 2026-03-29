#!/usr/bin/env ruby

require_relative "./phase2_acceptance_support"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
fingerprint = "phase2-process-run-runtime"
selector = ENV.fetch("PHASE2_PROCESS_SELECTOR", "candidate:openrouter/openai-gpt-5.4-live-acceptance")

Phase2AcceptanceSupport.reset_backend_state!
bootstrap = Phase2AcceptanceSupport.bootstrap_and_seed!
bundled = Phase2AcceptanceSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  environment_fingerprint: "phase2-process-run-environment",
  fingerprint: fingerprint,
  sdk_version: "fenix-0.1.0"
)
conversation_context = Phase2AcceptanceSupport.create_conversation!(deployment: bundled.fetch(:runtime).deployment)
run = Phase2AcceptanceSupport.start_turn_workflow_on_conversation!(
  conversation: conversation_context.fetch(:conversation),
  deployment: bundled.fetch(:runtime).deployment,
  content: "Start a long-running command and then close it gracefully.",
  root_node_key: "root",
  root_node_type: "turn_root",
  decision_source: "system",
  selector_source: "manual",
  selector: selector
)

workflow_run = run.fetch(:workflow_run).reload
turn = run.fetch(:turn).reload
model_context = workflow_run.execution_snapshot.model_context

Workflows::Mutate.call(
  workflow_run: workflow_run,
  nodes: [
    {
      node_key: "process",
      node_type: "turn_command",
      decision_source: "system",
      metadata: {},
    },
  ],
  edges: [
    { from_node_key: "root", to_node_key: "process" },
  ]
)

workflow_node = workflow_run.reload.workflow_nodes.find_by!(node_key: "process")
process_run = Processes::Start.call(
  workflow_node: workflow_node,
  execution_environment: bundled.fetch(:runtime).execution_environment,
  kind: "turn_command",
  command_line: "bin/echo phase2-process-run",
  timeout_seconds: 60,
  origin_message: turn.selected_input_message
)
Leases::Acquire.call(
  leased_resource: process_run,
  holder_key: bundled.fetch(:runtime).deployment.public_id,
  heartbeat_timeout_seconds: 30
)

occurred_at = Time.current
Conversations::RequestTurnInterrupt.call(turn: turn, occurred_at: occurred_at)
poll_occurred_at = occurred_at + 1.second
close_request = AgentControl::Poll.call(
  deployment: bundled.fetch(:runtime).deployment,
  limit: 10,
  occurred_at: poll_occurred_at
).find do |mailbox_item|
  mailbox_item.payload["resource_id"] == process_run.public_id
end

raise "expected process close request" if close_request.blank?

result = AgentControl::Report.call(
  deployment: bundled.fetch(:runtime).deployment,
  payload: {
    method_id: "resource_closed",
    protocol_message_id: "phase2-process-run-close",
    mailbox_item_id: close_request.public_id,
    close_request_id: close_request.public_id,
    resource_type: "ProcessRun",
    resource_id: process_run.public_id,
    close_outcome_kind: "graceful",
    close_outcome_payload: { "source" => "phase2_process_run_close_validation" },
  },
  occurred_at: poll_occurred_at
)

Phase2AcceptanceSupport.write_json(
  {
    "deployment_id" => bundled.fetch(:runtime).deployment.public_id,
    "execution_environment_id" => bundled.fetch(:runtime).execution_environment.public_id,
    "conversation_id" => conversation_context.fetch(:conversation).public_id,
    "turn_id" => turn.public_id,
    "workflow_run_id" => workflow_run.public_id,
    "process_run_id" => process_run.public_id,
    "close_request_id" => close_request.public_id,
    "provider_handle" => model_context["provider_handle"],
    "model_ref" => model_context["model_ref"],
    "api_model" => model_context["api_model"],
    "selector" => workflow_run.normalized_selector,
    "expected_dag_shape" => ["root->process"],
    "observed_dag_shape" => Phase2AcceptanceSupport.workflow_edge_keys(workflow_run),
    "expected_conversation_state" => {
      "conversation_lifecycle_state" => "active",
      "workflow_lifecycle_state" => "canceled",
      "workflow_wait_state" => "ready",
      "turn_lifecycle_state" => "canceled",
      "process_lifecycle_state" => "stopped",
      "process_close_state" => "closed",
      "process_close_outcome_kind" => "graceful",
    },
    "observed_conversation_state" => {
      "conversation_lifecycle_state" => conversation_context.fetch(:conversation).reload.lifecycle_state,
      "workflow_lifecycle_state" => workflow_run.reload.lifecycle_state,
      "workflow_wait_state" => workflow_run.wait_state,
      "turn_lifecycle_state" => turn.reload.lifecycle_state,
      "process_lifecycle_state" => process_run.reload.lifecycle_state,
      "process_close_state" => process_run.close_state,
      "process_close_outcome_kind" => process_run.close_outcome_kind,
      "close_request_status" => close_request.reload.status,
    },
    "report_result" => result.code,
    "workflow_node_event_states" => WorkflowNodeEvent.where(workflow_node: workflow_node).order(:ordinal).pluck(Arel.sql("payload ->> 'state'")),
  }
)
