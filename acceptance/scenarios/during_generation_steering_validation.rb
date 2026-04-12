#!/usr/bin/env ruby

require_relative "../lib/boot"

bundled_configuration = {
  enabled: true,
  agent_key: "acceptance-d-steering",
  display_name: "Acceptance Steering Runtime",
  visibility: "public",
  provisioning_origin: "system",
  lifecycle_state: "active",
  execution_runtime_kind: "local",
  execution_runtime_fingerprint: "acceptance-d-steering-environment",
  connection_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4100" },
  endpoint_metadata: {
    "transport" => "http",
    "base_url" => "http://127.0.0.1:4100",
    "runtime_manifest_path" => "/runtime/manifest",
  },
  fingerprint: "acceptance-d-steering-runtime",
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
    {
      "tool_name" => "subagent_spawn",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/subagent_spawn",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  profile_policy: {
    "main" => {
      "label" => "Main",
      "description" => "Primary interactive profile",
    },
    "researcher" => {
      "label" => "Researcher",
      "description" => "Delegated research profile",
      "default_subagent_profile" => true,
    },
  },
  canonical_config_schema: {
    "type" => "object",
    "properties" => {
      "interactive" => {
        "type" => "object",
        "properties" => {
          "selector" => { "type" => "string" },
          "profile" => { "type" => "string" },
        },
      },
      "subagents" => {
        "type" => "object",
        "properties" => {
          "enabled" => { "type" => "boolean" },
          "allow_nested" => { "type" => "boolean" },
          "max_depth" => { "type" => "integer" },
        },
      },
    },
  },
  conversation_override_schema: {
    "type" => "object",
    "properties" => {
      "subagents" => {
        "type" => "object",
        "properties" => {
          "enabled" => { "type" => "boolean" },
          "allow_nested" => { "type" => "boolean" },
          "max_depth" => { "type" => "integer" },
        },
      },
    },
  },
  default_canonical_config: {
    "sandbox" => "workspace-write",
    "interactive" => {
      "selector" => "role:main",
      "profile" => "main",
    },
    "subagents" => {
      "enabled" => true,
      "allow_nested" => true,
      "max_depth" => 3,
    },
  },
}.freeze

Acceptance::ManualSupport.reset_backend_state!
bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!(bundled_agent_configuration: { enabled: false })
registry = Installations::RegisterBundledAgentRuntime.call(
  installation: bootstrap.installation,
  configuration: bundled_configuration
)
binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent: registry.agent
).binding
workspace = binding.workspaces.find_by!(is_default: true)

def attach_output!(turn, content)
  output = Turns::CreateOutputVariant.call(turn: turn, content: content)
  turn.update!(selected_output_message: output)
  output
end

def build_active_work!(workspace:, registry:, policy:, content:)
  conversation = Conversations::CreateRoot.call(
    workspace: workspace,
    agent: registry.agent
  )
  conversation.update!(during_generation_input_policy: policy)
  turn = Turns::StartUserTurn.call(
    conversation: conversation,
    content: content,
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
  [conversation, turn, workflow_run]
end

reject_conversation, reject_turn, reject_workflow = build_active_work!(
  workspace: workspace,
  registry: registry,
  policy: "reject",
  content: "Reject policy input"
)
attach_output!(reject_turn, "Reject boundary output")
reject_error = nil
begin
  Turns::SteerCurrentInput.call(
    turn: reject_turn,
    content: "Rejected steering attempt"
  )
rescue ActiveRecord::RecordInvalid => error
  reject_error = {
    "messages" => error.record.errors[:base],
    "details" => error.record.errors.details[:base].map(&:stringify_keys),
  }
end

restart_conversation, restart_turn, restart_workflow = build_active_work!(
  workspace: workspace,
  registry: registry,
  policy: "restart",
  content: "Restart policy input"
)
attach_output!(restart_turn, "Restart boundary output")
restart_queued_turn = Turns::SteerCurrentInput.call(
  turn: restart_turn,
  content: "Restarted follow-up input"
)
restart_workflow.reload

queue_conversation, queue_turn, queue_workflow = build_active_work!(
  workspace: workspace,
  registry: registry,
  policy: "queue",
  content: "Queue policy input"
)
attach_output!(queue_turn, "Queue boundary output")
queue_queued_turn = Turns::SteerCurrentInput.call(
  turn: queue_turn,
  content: "Queued follow-up input"
)
queue_workflow.reload

feature_conversation = Conversations::CreateRoot.call(
  workspace: workspace,
  agent: registry.agent
)
feature_turn = Turns::StartUserTurn.call(
  conversation: feature_conversation,
  content: "Feature policy anchor",
  agent_definition_version: registry.agent_definition_version,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
feature_conversation.update!(
  enabled_feature_ids: Conversation::FEATURE_IDS - ["conversation_branching"]
)
feature_error = nil
begin
  Conversations::CreateBranch.call(
    parent: feature_conversation,
    historical_anchor_message_id: feature_turn.selected_input_message_id
  )
rescue ActiveRecord::RecordInvalid => error
  feature_error = error.record.errors.details.fetch(:base)
    .find { |candidate| candidate[:error] == :feature_not_enabled }
    &.stringify_keys
    &.transform_values(&:to_s)
end

stale_conversation = Conversations::CreateRoot.call(
  workspace: workspace,
  agent: registry.agent
)
stale_turn = Turns::StartUserTurn.call(
  conversation: stale_conversation,
  content: "Frozen stale-work input",
  agent_definition_version: registry.agent_definition_version,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
stale_workflow = Workflows::CreateForTurn.call(
  turn: stale_turn,
  root_node_key: "root",
  root_node_type: "turn_root",
  decision_source: "system",
  metadata: {},
  selector: "role:mock"
)
replacement_input = UserMessage.create!(
  installation: stale_turn.installation,
  conversation: stale_turn.conversation,
  turn: stale_turn,
  role: "user",
  slot: "input",
  variant_index: stale_turn.messages.where(slot: "input").maximum(:variant_index).to_i + 1,
  content: "Superseding input"
)
stale_turn.update!(selected_input_message: replacement_input)
stale_error = nil
begin
  ProviderExecution::WithFreshExecutionStateLock.call(
    workflow_node: stale_workflow.workflow_nodes.first
  ) { }
rescue => error
  stale_error = error.class.name
end

payload = {
  "scenario" => "during_generation_steering_validation",
  "reject" => {
    "conversation_id" => reject_conversation.public_id,
    "turn_id" => reject_turn.public_id,
    "workflow_run_id" => reject_workflow.public_id,
    "expected_conversation_state" => "conversation active; turn active; no queued follow-up created",
    "observed_conversation_state" => {
      "conversation_lifecycle_state" => reject_conversation.reload.lifecycle_state,
      "turn_lifecycle_state" => reject_turn.reload.lifecycle_state,
      "queued_turn_count" => reject_conversation.turns.where(lifecycle_state: "queued").count,
    },
    "error" => reject_error,
  },
  "restart" => {
    "conversation_id" => restart_conversation.public_id,
    "turn_id" => restart_turn.public_id,
    "workflow_run_id" => restart_workflow.public_id,
    "queued_turn_id" => restart_queued_turn.public_id,
    "expected_dag_shape" => "active workflow paused behind policy_gate; successor work moves to queued follow-up turn",
    "observed_dag_shape" => {
      "queued_turn_ids" => restart_conversation.turns.where(lifecycle_state: "queued").pluck(:public_id),
      "blocking_resource_id" => restart_workflow.blocking_resource_id,
      "expected_tail_message_id" => restart_queued_turn.origin_payload["expected_tail_message_id"],
      "queued_from_turn_id" => restart_queued_turn.origin_payload["queued_from_turn_id"],
    },
    "expected_conversation_state" => "workflow waiting on policy_gate and pointing at the queued follow-up turn",
    "observed_conversation_state" => {
      "wait_state" => restart_workflow.wait_state,
      "wait_reason_kind" => restart_workflow.wait_reason_kind,
      "queued_turn_lifecycle_state" => restart_queued_turn.lifecycle_state,
    },
  },
  "queue" => {
    "conversation_id" => queue_conversation.public_id,
    "turn_id" => queue_turn.public_id,
    "workflow_run_id" => queue_workflow.public_id,
    "queued_turn_id" => queue_queued_turn.public_id,
    "expected_dag_shape" => "active workflow keeps running; one queued follow-up turn is attached to the predecessor tail",
    "observed_dag_shape" => {
      "queued_turn_ids" => queue_conversation.turns.where(lifecycle_state: "queued").pluck(:public_id),
      "expected_tail_message_id" => queue_queued_turn.origin_payload["expected_tail_message_id"],
      "queued_from_turn_id" => queue_queued_turn.origin_payload["queued_from_turn_id"],
    },
    "expected_conversation_state" => "predecessor turn stays active and the workflow remains ready",
    "observed_conversation_state" => {
      "predecessor_turn_lifecycle_state" => queue_turn.reload.lifecycle_state,
      "workflow_wait_state" => queue_workflow.wait_state,
      "queued_turn_lifecycle_state" => queue_queued_turn.lifecycle_state,
    },
  },
  "feature_disabled" => {
    "conversation_id" => feature_conversation.public_id,
    "turn_id" => feature_turn.public_id,
    "expected_conversation_state" => "conversation_branching rejected by the current conversation policy",
    "observed_conversation_state" => feature_error,
  },
  "stale_work" => {
    "conversation_id" => stale_conversation.public_id,
    "turn_id" => stale_turn.public_id,
    "workflow_run_id" => stale_workflow.public_id,
    "expected_conversation_state" => "superseded provider work is rejected without mutating the current tail",
    "observed_conversation_state" => {
      "error_class" => stale_error,
      "selected_output_message_id" => stale_turn.reload.selected_output_message&.public_id,
      "current_selected_input_message_id" => stale_turn.selected_input_message.public_id,
      "workflow_wait_state" => stale_workflow.reload.wait_state,
    },
  },
}

payload["passed"] =
  payload.dig("reject", "error", "messages").to_a.include?("reject policy does not allow new input while active work exists") &&
  payload.dig("reject", "observed_conversation_state", "queued_turn_count") == 0 &&
  payload.dig("restart", "observed_conversation_state", "wait_state") == "waiting" &&
  payload.dig("restart", "observed_conversation_state", "wait_reason_kind") == "policy_gate" &&
  payload.dig("restart", "observed_dag_shape", "blocking_resource_id") == payload.dig("restart", "queued_turn_id") &&
  payload.dig("queue", "observed_conversation_state", "workflow_wait_state") == "ready" &&
  payload.dig("queue", "observed_conversation_state", "queued_turn_lifecycle_state") == "queued" &&
  payload.dig("feature_disabled", "observed_conversation_state", "error") == "feature_not_enabled" &&
  payload.dig("feature_disabled", "observed_conversation_state", "feature_id") == "conversation_branching" &&
  payload.dig("stale_work", "observed_conversation_state", "error_class") == "ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError" &&
  payload.dig("stale_work", "observed_conversation_state", "selected_output_message_id").nil?

Acceptance::ManualSupport.write_json(payload)
