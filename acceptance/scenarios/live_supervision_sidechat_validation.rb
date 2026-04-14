#!/usr/bin/env ruby
# ACCEPTANCE_MODE: hybrid_app_api
# This scenario must use app_api where a product/operator surface exists and only keep internal hooks for deterministic live waiting-work setup that still has no product entrypoint.

require "fileutils"
require_relative "../lib/boot"

def write_artifact_json(path, payload)
  FileUtils.mkdir_p(path.dirname)
  File.write(path, JSON.pretty_generate(payload))
end

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
artifact_stamp = ENV.fetch("LIVE_SUPERVISION_SIDECHAT_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-live-supervision-sidechat"
end
artifact_dir = AcceptanceHarness.repo_root.join("acceptance", "artifacts", artifact_stamp)
debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")
evidence_dir = artifact_dir.join("evidence")

Acceptance::ManualSupport.reset_backend_state!
bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!
app_api_session_token = Acceptance::ManualSupport.issue_app_api_session_token!(user: bootstrap.user)
bundled = Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  execution_runtime_fingerprint: "acceptance-live-supervision-environment",
  fingerprint: "acceptance-live-supervision-runtime"
)

FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(evidence_dir)

conversation_context = Acceptance::ManualSupport.create_conversation!(
  agent_definition_version: bundled.agent_definition_version
)
conversation = conversation_context.fetch(:conversation)
turn_workflow = Acceptance::ManualSupport.start_turn_workflow_on_conversation!(
  conversation: conversation,
  execution_runtime: bundled.execution_runtime,
  content: "Pause for operator confirmation before you continue the live supervision validation.",
  root_node_key: "turn_step_root",
  root_node_type: "turn_step",
  decision_source: "agent",
  selector: "candidate:dev/mock-model",
  initial_kind: "turn_step",
  initial_payload: { "step" => "live_supervision_probe" }
)

turn = turn_workflow.fetch(:turn)
workflow_run = turn_workflow.fetch(:workflow_run)
agent_task_run = turn_workflow.fetch(:agent_task_run) || AgentTaskRun.find_by!(workflow_run: workflow_run)
workflow_node = workflow_run.workflow_nodes.order(:ordinal, :id).first

workflow_node.update!(
  lifecycle_state: "running",
  presentation_policy: "ops_trackable",
  started_at: 3.minutes.ago,
  metadata: {}
)
agent_task_run.update!(
  lifecycle_state: "running",
  started_at: 3.minutes.ago,
  supervision_state: "running",
  request_summary: "Validate live supervision sidechat coverage",
  current_focus_summary: "Checking the live supervision sidechat path",
  recent_progress_summary: "Prepared the frozen supervision snapshot for an in-flight waiting turn.",
  blocked_summary: "Waiting for operator confirmation before continuing the validation.",
  next_step_hint: "Wait for operator confirmation before continuing the validation.",
  last_progress_at: 1.minute.ago,
  supervision_payload: {}
)
TurnTodoPlans::ApplyUpdate.call(
  agent_task_run: agent_task_run,
  payload: {
    "goal_summary" => "Validate live supervision sidechat coverage",
    "current_item_key" => "check-live-sidechat",
    "items" => [
      {
        "item_key" => "freeze-supervision-snapshot",
        "title" => "Freeze the supervision snapshot",
        "status" => "completed",
        "position" => 0,
        "kind" => "verification",
      },
      {
        "item_key" => "check-live-sidechat",
        "title" => "Checking the live supervision sidechat path",
        "status" => "in_progress",
        "position" => 1,
        "kind" => "verification",
      },
    ],
  },
  occurred_at: 1.minute.ago
)
AgentTaskProgressEntry.create!(
  installation: conversation.installation,
  agent_task_run: agent_task_run,
  sequence: 1,
  entry_kind: "progress_recorded",
  summary: "Prepared the frozen supervision snapshot for an in-flight waiting turn.",
  details_payload: {},
  occurred_at: 1.minute.ago
)
workflow_run.update!(
  wait_state: "waiting",
  wait_reason_kind: "human_interaction",
  wait_reason_payload: {},
  waiting_since_at: 20.seconds.ago,
  blocking_resource_type: "HumanInteractionRequest",
  blocking_resource_id: "acceptance-live-sidechat-blocker"
)
Conversations::UpdateSupervisionState.call(
  conversation: conversation,
  occurred_at: Time.current
)

transcript_before = Acceptance::ManualSupport.app_api_conversation_transcript!(
  conversation_id: conversation.public_id,
  session_token: app_api_session_token
)
diagnostics = Acceptance::ManualSupport.wait_for_app_api_conversation_diagnostics_materialized!(
  conversation_id: conversation.public_id,
  session_token: app_api_session_token
)
turn_snapshot = diagnostics.fetch("turns").fetch("items").find { |item| item.fetch("turn_id") == turn.public_id }

session_created = Acceptance::ManualSupport.app_api_create_conversation_supervision_session!(
  conversation_id: conversation.public_id,
  responder_strategy: "builtin",
  session_token: app_api_session_token
)
supervision_session_id = session_created.dig("conversation_supervision_session", "supervision_session_id")

status_probe = Acceptance::ManualSupport.app_api_append_conversation_supervision_message!(
  conversation_id: conversation.public_id,
  supervision_session_id: supervision_session_id,
  content: "What are you doing right now and what changed most recently?",
  session_token: app_api_session_token
)
blocker_probe = Acceptance::ManualSupport.app_api_append_conversation_supervision_message!(
  conversation_id: conversation.public_id,
  supervision_session_id: supervision_session_id,
  content: "What are you waiting on right now?",
  session_token: app_api_session_token
)
supervision_messages = Acceptance::ManualSupport.app_api_conversation_supervision_messages!(
  conversation_id: conversation.public_id,
  supervision_session_id: supervision_session_id,
  session_token: app_api_session_token
)
transcript_after = Acceptance::ManualSupport.app_api_conversation_transcript!(
  conversation_id: conversation.public_id,
  session_token: app_api_session_token
)

debug_export_download = Acceptance::ManualSupport.app_api_debug_export_conversation!(
  conversation_id: conversation.public_id,
  session_token: app_api_session_token,
  destination_path: debug_export_path
)
debug_payload = Acceptance::ManualSupport.extract_debug_export_payload!(
  debug_export_download.dig("download", "path")
)
export_sessions = debug_payload.fetch("conversation_supervision_sessions")
export_messages = debug_payload.fetch("conversation_supervision_messages")
export_session_messages = export_messages.select do |item|
  item.fetch("supervision_session_id") == supervision_session_id
end

write_artifact_json(evidence_dir.join("conversation-supervision-session.json"), session_created)
write_artifact_json(
  evidence_dir.join("conversation-supervision-probe.json"),
  {
    "status_probe" => status_probe,
    "blocker_probe" => blocker_probe,
    "messages" => supervision_messages,
  }
)
write_artifact_json(
  evidence_dir.join("conversation-debug-export.json"),
  {
    "manifest" => debug_payload.fetch("manifest"),
    "conversation_supervision_sessions" => export_sessions,
    "conversation_supervision_messages" => export_session_messages,
  }
)

observed_dag_shape = workflow_run.reload.workflow_nodes
  .order(:ordinal, :created_at, :id)
  .map(&:node_key)
expected_dag_shape = ["turn_step_root"]
observed_conversation_state = {
  "conversation_state" => diagnostics.dig("conversation", "snapshot", "lifecycle_state"),
  "turn_lifecycle_state" => turn_snapshot&.fetch("lifecycle_state"),
  "workflow_wait_state" => workflow_run.reload.wait_state,
  "machine_status" => blocker_probe.dig("machine_status", "overall_state"),
}
expected_conversation_state = {
  "conversation_state" => "active",
  "turn_lifecycle_state" => "active",
  "workflow_wait_state" => "waiting",
  "machine_status" => "blocked",
}

status_content = status_probe.dig("human_sidechat", "content").to_s
blocker_content = blocker_probe.dig("human_sidechat", "content").to_s
message_roles = supervision_messages.fetch("items").map { |item| item.fetch("role") }
transcript_before_ids = transcript_before.fetch("items").map { |item| item.fetch("id") }
transcript_after_ids = transcript_after.fetch("items").map { |item| item.fetch("id") }

result = Acceptance::ManualSupport.scenario_result(
  scenario: "live_supervision_sidechat_validation",
  expected_dag_shape: expected_dag_shape,
  observed_dag_shape: observed_dag_shape,
  expected_conversation_state: expected_conversation_state,
  observed_conversation_state: observed_conversation_state,
  proof_artifact_path: debug_export_path.to_s,
  extra: {
    "conversation_id" => conversation.public_id,
    "turn_id" => turn.public_id,
    "workflow_run_id" => workflow_run.public_id,
    "supervision_session_id" => supervision_session_id,
    "status_probe_content" => status_content,
    "blocker_probe_content" => blocker_content,
    "message_roles" => message_roles,
    "transcript_before_ids" => transcript_before_ids,
    "transcript_after_ids" => transcript_after_ids,
    "export_path" => debug_export_path.to_s,
    "evidence_paths" => {
      "session" => evidence_dir.join("conversation-supervision-session.json").to_s,
      "probe" => evidence_dir.join("conversation-supervision-probe.json").to_s,
      "debug_export" => evidence_dir.join("conversation-debug-export.json").to_s,
    },
  }
)

result["passed"] &&=
  diagnostics.dig("conversation", "diagnostics_status").in?(%w[ready stale]) &&
  diagnostics.dig("turns", "diagnostics_status").in?(%w[ready stale]) &&
  turn_snapshot.present? &&
  status_content.match?(/right now|currently/i) &&
  status_content.match?(/most recently/i) &&
  !status_content.match?(/execution runtime completed|turn completed/i) &&
  blocker_content.match?(/operator confirmation|waiting|blocker/i) &&
  message_roles == %w[user supervisor_agent user supervisor_agent] &&
  transcript_before_ids == transcript_after_ids &&
  export_sessions.any? { |item| item.fetch("supervision_session_id") == supervision_session_id } &&
  export_session_messages.length == 4 &&
  export_session_messages.map { |item| item.fetch("role") } == message_roles

Acceptance::ManualSupport.write_json(result)
