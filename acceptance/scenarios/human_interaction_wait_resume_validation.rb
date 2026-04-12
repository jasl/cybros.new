#!/usr/bin/env ruby

require_relative "../lib/boot"

bundled_configuration = {
  enabled: true,
  agent_key: "acceptance-d-human",
  display_name: "Acceptance Human Wait Runtime",
  visibility: "public",
  provisioning_origin: "system",
  lifecycle_state: "active",
  execution_runtime_kind: "local",
  execution_runtime_fingerprint: "acceptance-d-human-environment",
  connection_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4100" },
  endpoint_metadata: {
    "transport" => "http",
    "base_url" => "http://127.0.0.1:4100",
    "runtime_manifest_path" => "/runtime/manifest",
  },
  fingerprint: "acceptance-d-human-runtime",
  protocol_version: "2026-03-24",
  sdk_version: "fenix-0.1.0",
  protocol_methods: [
    { "method_id" => "agent_health" },
    { "method_id" => "capabilities_handshake" },
  ],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: {
    "type" => "object",
    "properties" => {
      "interactive" => {
        "type" => "object",
        "properties" => {
          "selector" => { "type" => "string" },
        },
      },
    },
  },
  conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
  default_config_snapshot: {
    "sandbox" => "workspace-write",
    "interactive" => { "selector" => "role:main" },
  },
}.freeze

Acceptance::ManualSupport.reset_backend_state!
bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!(bundled_agent_configuration: { enabled: false })
registry = Installations::RegisterBundledAgentRuntime.call(
  installation: bootstrap.installation,
  configuration: bundled_configuration
)
execution_runtime_connection = registry.execution_runtime_connection
binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent: registry.agent
).binding
workspace = binding.workspaces.find_by!(is_default: true)

conversation = Conversations::CreateRoot.call(
  workspace: workspace,
  agent: registry.agent
)
turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "Need operator confirmation before continuing.",
  agent_definition_version: registry.agent_definition_version,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
workflow_run = Workflows::CreateForTurn.call(
  turn: turn,
  root_node_key: "root",
  root_node_type: "turn_root",
  decision_source: "system",
  metadata: {},
  selector: "role:mock"
)
Workflows::Mutate.call(
  workflow_run: workflow_run,
  nodes: [
    {
      node_key: "agent_turn_step",
      node_type: "turn_step",
      decision_source: "agent",
      metadata: {},
    },
  ],
  edges: [
    { from_node_key: "root", to_node_key: "agent_turn_step" },
  ]
)
workflow_node = workflow_run.reload.workflow_nodes.find_by!(node_key: "agent_turn_step")
agent_task_run = AgentTaskRun.create!(
  installation: workflow_run.installation,
  agent: registry.agent,
  workflow_run: workflow_run,
  workflow_node: workflow_node,
  conversation: conversation,
  turn: turn,
  kind: "turn_step",
  lifecycle_state: "queued",
  logical_work_id: "turn-step:#{turn.public_id}:agent_turn_step",
  attempt_no: 1,
  task_payload: { "step" => "agent_turn_step" },
  progress_payload: {},
  terminal_payload: {}
)
mailbox_item = AgentControl::CreateExecutionAssignment.call(
  agent_task_run: agent_task_run,
  payload: { "task_payload" => agent_task_run.task_payload },
  dispatch_deadline_at: 5.minutes.from_now,
  execution_hard_deadline_at: 10.minutes.from_now
)

Acceptance::ManualSupport.dispatch_execution_report!(
  agent_definition_version: registry.agent_definition_version,
  execution_runtime_connection: execution_runtime_connection,
  mailbox_item: mailbox_item,
  agent_task_run: agent_task_run,
  method_id: "execution_started",
  protocol_message_id: "acceptance-human-start",
  expected_duration_seconds: 30
)
Acceptance::ManualSupport.dispatch_execution_report!(
  agent_definition_version: registry.agent_definition_version,
  execution_runtime_connection: execution_runtime_connection,
  mailbox_item: mailbox_item,
  agent_task_run: agent_task_run,
  method_id: "execution_complete",
  protocol_message_id: "acceptance-human-complete",
  terminal_payload: {
    "output" => "Need operator input",
    "wait_transition_requested" => {
      "batch_manifest" => {
        "batch_id" => "acceptance-human-batch",
        "resume_policy" => "re_enter_agent",
        "successor" => {
          "node_key" => "agent_step_2",
          "node_type" => "turn_step",
        },
        "stages" => [
          {
            "stage_index" => 0,
            "dispatch_mode" => "serial",
            "completion_barrier" => "none",
            "intents" => [
              {
                "intent_id" => "acceptance-human-batch:human",
                "intent_kind" => "human_interaction_request",
                "node_key" => "human_gate",
                "node_type" => "human_interaction",
                "requirement" => "required",
                "conflict_scope" => "human_interaction",
                "presentation_policy" => "user_projectable",
                "durable_outcome" => "accepted",
                "payload" => {
                  "request_type" => "HumanTaskRequest",
                  "blocking" => true,
                  "request_payload" => {
                    "instructions" => "Confirm the operator decision before continuing.",
                  },
                },
                "idempotency_key" => "acceptance-human-batch:human",
              },
            ],
          },
        ],
      },
    },
  }
)

workflow_run.reload
request = HumanTaskRequest.find_by!(
  workflow_run: workflow_run,
  workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "human_gate")
)
before_edges = WorkflowEdge.where(workflow_run: workflow_run).includes(:from_node, :to_node).map do |edge|
  "#{edge.from_node.node_key}->#{edge.to_node.node_key}"
end.sort
before_state = {
  "conversation_lifecycle_state" => conversation.reload.lifecycle_state,
  "turn_lifecycle_state" => turn.reload.lifecycle_state,
  "workflow_wait_state" => workflow_run.wait_state,
  "workflow_wait_reason_kind" => workflow_run.wait_reason_kind,
  "blocking_resource_id" => workflow_run.blocking_resource_id,
}

HumanInteractions::CompleteTask.call(
  human_task_request: request,
  completion_payload: { "confirmed" => true }
)

workflow_run.reload
successor_task = AgentTaskRun.where(workflow_run: workflow_run).where.not(id: agent_task_run.id).order(:created_at, :id).last
raise "expected successor task after human interaction resolution" if successor_task.blank?

successor_node = successor_task.workflow_node
after_edges = WorkflowEdge.where(workflow_run: workflow_run).includes(:from_node, :to_node).map do |edge|
  "#{edge.from_node.node_key}->#{edge.to_node.node_key}"
end.sort
after_state = {
  "conversation_lifecycle_state" => conversation.reload.lifecycle_state,
  "turn_lifecycle_state" => turn.reload.lifecycle_state,
  "workflow_wait_state" => workflow_run.wait_state,
  "workflow_wait_reason_kind" => workflow_run.wait_reason_kind,
  "successor_task_lifecycle_state" => successor_task.lifecycle_state,
}

payload = {
  "scenario" => "human_interaction_wait_resume_validation",
  "conversation_id" => conversation.public_id,
  "turn_id" => turn.public_id,
  "workflow_run_id" => workflow_run.public_id,
  "human_interaction_request_id" => request.public_id,
  "successor_agent_task_run_id" => successor_task.public_id,
  "expected_dag_shape_before" => [
    "root->agent_turn_step",
    "agent_turn_step->human_gate",
  ],
  "observed_dag_shape_before" => before_edges,
  "expected_conversation_state_before" => "conversation active; turn active; workflow waiting on human_interaction",
  "observed_conversation_state_before" => before_state,
  "expected_dag_shape_after" => [
    "root->agent_turn_step",
    "agent_turn_step->human_gate",
    "human_gate->agent_step_2",
  ],
  "observed_dag_shape_after" => after_edges,
  "expected_conversation_state_after" => "conversation active; turn active; workflow ready with a queued successor step",
  "observed_conversation_state_after" => after_state,
  "successor_node_key" => successor_node.node_key,
}

payload["passed"] =
  payload["human_interaction_request_id"].present? &&
  payload["observed_dag_shape_before"] == ["agent_turn_step->human_gate", "root->agent_turn_step"] &&
  payload.dig("observed_conversation_state_before", "workflow_wait_state") == "waiting" &&
  payload.dig("observed_conversation_state_before", "workflow_wait_reason_kind") == "human_interaction" &&
  payload.dig("observed_conversation_state_before", "blocking_resource_id") == payload["human_interaction_request_id"] &&
  payload["observed_dag_shape_after"].include?("human_gate->#{successor_node.node_key}") &&
  payload.dig("observed_conversation_state_after", "workflow_wait_state") == "ready" &&
  payload.dig("observed_conversation_state_after", "successor_task_lifecycle_state") == "queued"

Acceptance::ManualSupport.write_json(payload)
