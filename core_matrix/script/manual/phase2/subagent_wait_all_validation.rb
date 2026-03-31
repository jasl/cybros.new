#!/usr/bin/env ruby

require_relative "../manual_acceptance_support"

bundled_configuration = {
  enabled: true,
  agent_key: "phase2-d-subagents",
  display_name: "Phase 2 Subagent Runtime",
  visibility: "global",
  lifecycle_state: "active",
  environment_kind: "local",
  environment_fingerprint: "phase2-d-subagents-environment",
  connection_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4100" },
  endpoint_metadata: {
    "transport" => "http",
    "base_url" => "http://127.0.0.1:4100",
    "runtime_manifest_path" => "/runtime/manifest",
    "prepare_round_path" => "/runtime/rounds/prepare",
    "execute_program_tool_path" => "/runtime/program_tools/execute",
  },
  fingerprint: "phase2-d-subagents-runtime",
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
  profile_catalog: {
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
  config_schema_snapshot: {
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
  conversation_override_schema_snapshot: {
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
  default_config_snapshot: {
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

ManualAcceptanceSupport.reset_backend_state!
bootstrap = ManualAcceptanceSupport.bootstrap_and_seed!(bundled_agent_configuration: { enabled: false })
registry = Installations::RegisterBundledAgentRuntime.call(
  installation: bootstrap.installation,
  configuration: bundled_configuration
)
binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent_installation: registry.agent_installation
).binding
workspace = binding.workspaces.find_by!(is_default: true)

conversation = Conversations::CreateRoot.call(
  workspace: workspace,
  execution_environment: registry.execution_environment,
  agent_deployment: registry.deployment
)
turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "Delegate both research tasks and wait for them to finish.",
  agent_deployment: registry.deployment,
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
      decision_source: "agent_program",
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
  agent_installation: registry.agent_installation,
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

AgentControl::Poll.call(deployment: registry.deployment, limit: 10)
AgentControl::Report.call(
  deployment: registry.deployment,
  method_id: "execution_started",
  protocol_message_id: "phase2-subagents-start",
  mailbox_item_id: mailbox_item.public_id,
  agent_task_run_id: agent_task_run.public_id,
  logical_work_id: agent_task_run.logical_work_id,
  attempt_no: agent_task_run.attempt_no,
  expected_duration_seconds: 30
)
AgentControl::Report.call(
  deployment: registry.deployment,
  method_id: "execution_complete",
  protocol_message_id: "phase2-subagents-complete",
  mailbox_item_id: mailbox_item.public_id,
  agent_task_run_id: agent_task_run.public_id,
  logical_work_id: agent_task_run.logical_work_id,
  attempt_no: agent_task_run.attempt_no,
  terminal_payload: {
    "output" => "Delegated both research tasks",
    "wait_transition_requested" => {
      "batch_manifest" => {
        "batch_id" => "phase2-subagents-batch",
        "resume_policy" => "re_enter_agent",
        "successor" => {
          "node_key" => "agent_step_2",
          "node_type" => "turn_step",
        },
        "stages" => [
          {
            "stage_index" => 0,
            "dispatch_mode" => "parallel",
            "completion_barrier" => "wait_all",
            "intents" => [
              {
                "intent_id" => "phase2-subagents-batch:subagent:0",
                "intent_kind" => "subagent_spawn",
                "node_key" => "subagent_alpha",
                "node_type" => "subagent_spawn",
                "requirement" => "required",
                "conflict_scope" => "subagent_pool",
                "presentation_policy" => "ops_trackable",
                "durable_outcome" => "accepted",
                "payload" => {
                  "content" => "Investigate alpha",
                  "scope" => "conversation",
                  "profile_key" => "researcher",
                  "task_payload" => {},
                },
                "idempotency_key" => "phase2-subagents-batch:subagent:0",
              },
              {
                "intent_id" => "phase2-subagents-batch:subagent:1",
                "intent_kind" => "subagent_spawn",
                "node_key" => "subagent_beta",
                "node_type" => "subagent_spawn",
                "requirement" => "required",
                "conflict_scope" => "subagent_pool",
                "presentation_policy" => "ops_trackable",
                "durable_outcome" => "accepted",
                "payload" => {
                  "content" => "Investigate beta",
                  "scope" => "conversation",
                  "profile_key" => "researcher",
                  "task_payload" => {},
                },
                "idempotency_key" => "phase2-subagents-batch:subagent:1",
              },
            ],
          },
        ],
      },
    },
  }
)

workflow_run.reload
before_edges = WorkflowEdge.where(workflow_run: workflow_run).includes(:from_node, :to_node).map do |edge|
  "#{edge.from_node.node_key}->#{edge.to_node.node_key}"
end.sort
subagent_sessions = SubagentSession.where(owner_conversation: conversation).order(:created_at).to_a
child_tasks = AgentTaskRun.where(origin_turn: turn, kind: "subagent_step").order(:created_at).to_a
before_state = {
  "conversation_lifecycle_state" => conversation.reload.lifecycle_state,
  "turn_lifecycle_state" => turn.reload.lifecycle_state,
  "workflow_wait_state" => workflow_run.wait_state,
  "workflow_wait_reason_kind" => workflow_run.wait_reason_kind,
  "blocking_resource_id" => workflow_run.blocking_resource_id,
  "subagent_session_ids" => workflow_run.wait_reason_payload["subagent_session_ids"],
}

first_child = child_tasks.first
first_mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: first_child, item_type: "execution_assignment")
AgentControl::Poll.call(deployment: registry.deployment, limit: 10)
AgentControl::Report.call(
  deployment: registry.deployment,
  method_id: "execution_started",
  protocol_message_id: "phase2-subagents-child-1-start",
  mailbox_item_id: first_mailbox_item.public_id,
  agent_task_run_id: first_child.public_id,
  logical_work_id: first_child.logical_work_id,
  attempt_no: first_child.attempt_no,
  expected_duration_seconds: 30
)
AgentControl::Report.call(
  deployment: registry.deployment,
  method_id: "execution_complete",
  protocol_message_id: "phase2-subagents-child-1-complete",
  mailbox_item_id: first_mailbox_item.public_id,
  agent_task_run_id: first_child.public_id,
  logical_work_id: first_child.logical_work_id,
  attempt_no: first_child.attempt_no,
  terminal_payload: { "output" => "alpha done" }
)
after_first_child_state = {
  "workflow_wait_state" => workflow_run.reload.wait_state,
  "workflow_wait_reason_kind" => workflow_run.wait_reason_kind,
}

second_child = child_tasks.second
second_mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: second_child, item_type: "execution_assignment")
AgentControl::Poll.call(deployment: registry.deployment, limit: 10)
AgentControl::Report.call(
  deployment: registry.deployment,
  method_id: "execution_started",
  protocol_message_id: "phase2-subagents-child-2-start",
  mailbox_item_id: second_mailbox_item.public_id,
  agent_task_run_id: second_child.public_id,
  logical_work_id: second_child.logical_work_id,
  attempt_no: second_child.attempt_no,
  expected_duration_seconds: 30
)
AgentControl::Report.call(
  deployment: registry.deployment,
  method_id: "execution_complete",
  protocol_message_id: "phase2-subagents-child-2-complete",
  mailbox_item_id: second_mailbox_item.public_id,
  agent_task_run_id: second_child.public_id,
  logical_work_id: second_child.logical_work_id,
  attempt_no: second_child.attempt_no,
  terminal_payload: { "output" => "beta done" }
)

workflow_run.reload
successor_node = workflow_run.workflow_nodes.find_by!(node_key: "agent_step_2")
successor_task = AgentTaskRun.find_by!(workflow_run: workflow_run, workflow_node: successor_node)
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
  "scenario" => "subagent_wait_all_validation",
  "conversation_id" => conversation.public_id,
  "turn_id" => turn.public_id,
  "workflow_run_id" => workflow_run.public_id,
  "subagent_session_ids" => subagent_sessions.map(&:public_id),
  "child_conversation_ids" => subagent_sessions.map { |session| session.conversation.public_id },
  "successor_agent_task_run_id" => successor_task.public_id,
  "expected_dag_shape_before" => [
    "root->agent_turn_step",
    "agent_turn_step->subagent_alpha",
    "agent_turn_step->subagent_beta",
  ],
  "observed_dag_shape_before" => before_edges,
  "expected_conversation_state_before" => "conversation active; turn active; workflow waiting on subagent_barrier",
  "observed_conversation_state_before" => before_state,
  "expected_conversation_state_after_first_child" => "workflow still waiting on the same barrier until every child finishes",
  "observed_conversation_state_after_first_child" => after_first_child_state,
  "expected_dag_shape_after" => [
    "root->agent_turn_step",
    "agent_turn_step->subagent_alpha",
    "agent_turn_step->subagent_beta",
    "subagent_alpha->agent_step_2",
    "subagent_beta->agent_step_2",
  ],
  "observed_dag_shape_after" => after_edges,
  "expected_conversation_state_after" => "conversation active; turn active; workflow ready with a queued successor step",
  "observed_conversation_state_after" => after_state,
}

payload["passed"] =
  payload["subagent_session_ids"].size == 2 &&
  payload["observed_dag_shape_before"] == ["agent_turn_step->subagent_alpha", "agent_turn_step->subagent_beta", "root->agent_turn_step"] &&
  payload.dig("observed_conversation_state_before", "workflow_wait_state") == "waiting" &&
  payload.dig("observed_conversation_state_before", "workflow_wait_reason_kind") == "subagent_barrier" &&
  payload.dig("observed_conversation_state_after_first_child", "workflow_wait_state") == "waiting" &&
  payload["observed_dag_shape_after"] == ["agent_turn_step->subagent_alpha", "agent_turn_step->subagent_beta", "root->agent_turn_step", "subagent_alpha->agent_step_2", "subagent_beta->agent_step_2"] &&
  payload.dig("observed_conversation_state_after", "workflow_wait_state") == "ready" &&
  payload.dig("observed_conversation_state_after", "successor_task_lifecycle_state") == "queued"

ManualAcceptanceSupport.write_json(payload)
