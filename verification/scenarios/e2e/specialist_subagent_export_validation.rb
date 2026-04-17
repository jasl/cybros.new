#!/usr/bin/env ruby
# VERIFICATION_MODE: hybrid_app_api
# This scenario validates specialist export/review proof through app_api where available, while deterministic specialist spawning still has no equivalent app_api forcing surface.

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "verification/hosted/core_matrix"

artifact_stamp = ENV.fetch("SPECIALIST_SUBAGENT_EXPORT_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-specialist-subagent-export-validation"
end
artifact_dir = Verification.repo_root.join("verification", "artifacts", artifact_stamp)
conversation_export_path = artifact_dir.join("exports", "conversation-export.zip")
conversation_debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")

def read_zip_json(zip_path, entry_name)
  Zip::File.open(zip_path.to_s) do |zip|
    entry = zip.find_entry(entry_name)
    raise "missing #{entry_name} in #{zip_path}" if entry.nil?

    JSON.parse(entry.get_input_stream.read)
  end
end

bundled_configuration = {
  enabled: true,
  agent_key: "verification-specialist-export",
  display_name: "Verification Specialist Export Runtime",
  visibility: "public",
  provisioning_origin: "system",
  lifecycle_state: "active",
  execution_runtime_kind: "local",
  execution_runtime_fingerprint: "verification-specialist-export-environment",
  execution_runtime_connection_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4100" },
  endpoint_metadata: {
    "transport" => "http",
    "base_url" => "http://127.0.0.1:4100",
    "runtime_manifest_path" => "/runtime/manifest",
  },
  fingerprint: "verification-specialist-export-runtime",
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
  workspace_agent_settings_schema: {
    "type" => "object",
    "properties" => {},
  },
  default_workspace_agent_settings: {},
  default_canonical_config: {
    "sandbox" => "workspace-write",
    "interactive" => {
      "selector" => "role:mock",
      "profile" => "pragmatic",
    },
    "subagents" => {
      "enabled" => true,
      "allow_nested" => true,
      "max_depth" => 2,
    },
  },
}.freeze

Verification::ManualSupport.reset_backend_state!
bootstrap = Verification::ManualSupport.bootstrap_and_seed!(bundled_agent_configuration: { enabled: false })
app_api_session_token = Verification::ManualSupport.issue_app_api_session_token!(user: bootstrap.user)
registry = Installations::RegisterBundledAgentRuntime.call(
  installation: bootstrap.installation,
  configuration: bundled_configuration
)
execution_runtime_connection = registry.execution_runtime_connection
workspace = Workspaces::MaterializeDefault.call(user: bootstrap.user, agent: registry.agent)

FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)

conversation = Conversations::CreateRoot.call(workspace: workspace, agent: registry.agent)
turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "Force one tester specialist so export proof can validate delegation artifacts.",
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
  user: workflow_run.user,
  workspace: workflow_run.workspace,
  agent: workflow_run.agent,
  workflow_run: workflow_run,
  workflow_node: workflow_node,
  conversation: conversation,
  turn: turn,
  execution_runtime: workflow_run.execution_runtime,
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

Verification::ManualSupport.dispatch_execution_report!(
  agent_definition_version: registry.agent_definition_version,
  execution_runtime_connection: execution_runtime_connection,
  mailbox_item: mailbox_item,
  agent_task_run: agent_task_run,
  method_id: "execution_started",
  protocol_message_id: "verification-specialist-start",
  expected_duration_seconds: 30
)
Verification::ManualSupport.dispatch_execution_report!(
  agent_definition_version: registry.agent_definition_version,
  execution_runtime_connection: execution_runtime_connection,
  mailbox_item: mailbox_item,
  agent_task_run: agent_task_run,
  method_id: "execution_complete",
  protocol_message_id: "verification-specialist-complete",
  terminal_payload: {
    "output" => "Delegated the verification step to tester",
    "wait_transition_requested" => {
      "batch_manifest" => {
        "batch_id" => "verification-specialist-batch",
        "resume_policy" => "re_enter_agent",
        "successor" => {
          "node_key" => "agent_finalize",
          "node_type" => "turn_step",
        },
        "stages" => [
          {
            "stage_index" => 0,
            "dispatch_mode" => "parallel",
            "completion_barrier" => "wait_all",
            "intents" => [
              {
                "intent_id" => "verification-specialist-batch:subagent:0",
                "intent_kind" => "subagent_spawn",
                "node_key" => "tester_subagent",
                "node_type" => "subagent_spawn",
                "requirement" => "required",
                "conflict_scope" => "subagent_pool",
                "presentation_policy" => "ops_trackable",
                "durable_outcome" => "accepted",
                "payload" => {
                  "content" => "Run one verification pass and summarize it for the parent turn.",
                  "scope" => "conversation",
                  "profile_key" => "tester",
                  "task_payload" => {},
                },
                "idempotency_key" => "verification-specialist-batch:subagent:0",
              },
            ],
          },
        ],
      },
    },
  }
)

workspace_agent = workspace.primary_workspace_agent || raise("expected default workspace agent")
conversation_export = Verification::ManualSupport.app_api_export_conversation!(
  conversation_id: conversation.public_id,
  session_token: app_api_session_token,
  destination_path: conversation_export_path
)
conversation_debug_export = Verification::ManualSupport.app_api_debug_export_conversation!(
  conversation_id: conversation.public_id,
  session_token: app_api_session_token,
  destination_path: conversation_debug_export_path
)

debug_payload = Verification::ManualSupport.extract_debug_export_payload!(
  conversation_debug_export.dig("download", "path")
)
export_payload = read_zip_json(conversation_export_path, "conversation.json")

Verification::CapstoneReviewArtifacts.install!(
  artifact_dir: artifact_dir,
  conversation_export_path: conversation_export_path,
  conversation_debug_export_path: conversation_debug_export_path,
  turn_feed: { "items" => [] },
  turn_runtime_events: { "summary" => { "event_count" => 0, "lane_count" => 0 }, "segments" => [] },
  debug_payload: debug_payload,
  workflow_run_id: workflow_run.public_id
)

delegation_summary = export_payload.fetch("delegation_summary")
subagent_connections = debug_payload.fetch("subagent_connections")
workflow_review = artifact_dir.join("review", "workflow-mermaid.md").read

expected_dag_shape = %w[root agent_turn_step tester_subagent]
observed_dag_shape = debug_payload.fetch("workflow_nodes")
  .select { |node| node.fetch("turn_id") == turn.public_id }
  .sort_by { |node| [node.fetch("ordinal"), node.fetch("created_at").to_s] }
  .map { |node| node.fetch("node_key") }
expected_conversation_state = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "active",
  "workflow_wait_state" => "waiting",
  "turn_lifecycle_state" => "active",
}
observed_conversation_state = {
  "conversation_state" => conversation.reload.lifecycle_state,
  "workflow_lifecycle_state" => workflow_run.reload.lifecycle_state,
  "workflow_wait_state" => workflow_run.wait_state,
  "turn_lifecycle_state" => turn.reload.lifecycle_state,
}

result = Verification::ManualSupport.scenario_result(
  scenario: "specialist_subagent_export_validation",
  expected_dag_shape: expected_dag_shape,
  observed_dag_shape: observed_dag_shape,
  expected_conversation_state: expected_conversation_state,
  observed_conversation_state: observed_conversation_state,
  proof_artifact_path: conversation_debug_export_path.to_s,
  extra: {
    "workspace_agent_id" => workspace_agent.public_id,
    "conversation_export_path" => conversation_export_path.to_s,
    "conversation_debug_export_path" => conversation_debug_export_path.to_s,
    "delegation_summary" => delegation_summary,
    "subagent_connections" => subagent_connections,
    "workflow_mermaid_review_path" => artifact_dir.join("review", "workflow-mermaid.md").to_s,
  }
)
result["passed"] &&=
  delegation_summary.any? { |entry| entry.fetch("profile_key") == "tester" } &&
  subagent_connections.any? { |entry| entry.fetch("profile_key") == "tester" } &&
  workflow_review.include?("profile: tester")

Verification::ManualSupport.write_json(result)
