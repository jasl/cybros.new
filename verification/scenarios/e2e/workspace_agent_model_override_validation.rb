#!/usr/bin/env ruby
# VERIFICATION_MODE: app_api_surface
# This scenario validates mounted model override behavior through app_api only.

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "verification/hosted/core_matrix"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
artifact_stamp = ENV.fetch("WORKSPACE_AGENT_MODEL_OVERRIDE_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-workspace-agent-model-override-validation"
end
artifact_dir = Verification.repo_root.join("verification", "artifacts", artifact_stamp)
debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")
content = ENV.fetch(
  "WORKSPACE_AGENT_MODEL_OVERRIDE_PROMPT",
  "Reply briefly in Chinese to confirm the mounted model override path was exercised."
)

Verification::ManualSupport.reset_backend_state!
bootstrap = Verification::ManualSupport.bootstrap_and_seed!
app_api_session_token = Verification::ManualSupport.issue_app_api_session_token!(user: bootstrap.user)
bundled = Verification::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  execution_runtime_fingerprint: "verification-workspace-agent-model-override-environment",
  fingerprint: "verification-workspace-agent-model-override-runtime"
)
workspace_context = Verification::ManualSupport.enable_default_workspace!(
  agent_definition_version: bundled.agent_definition_version
)

FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)

settings_payload = {
  core_matrix: {
    interactive: {
      model_selector: "role:mock",
    },
  },
}

Verification::ManualSupport.app_api_patch_json(
  "/app_api/workspaces/#{workspace_context.fetch(:workspace).public_id}/workspace_agents/#{workspace_context.fetch(:workspace_agent).public_id}",
  { settings_payload: settings_payload },
  session_token: app_api_session_token
)

created = nil
terminal = nil

Verification::ManualSupport.with_fenix_control_worker_for_registration!(registration: bundled) do
  created = Verification::ManualSupport.app_api_create_conversation!(
    workspace_agent_id: workspace_context.fetch(:workspace_agent).public_id,
    content: content,
    session_token: app_api_session_token
  )
  terminal = Verification::ManualSupport.wait_for_app_api_turn_terminal!(
    conversation_id: created.dig("conversation", "conversation_id"),
    turn_id: created.fetch("turn_id"),
    session_token: app_api_session_token
  )
end

conversation_id = created.dig("conversation", "conversation_id")
turn_id = created.fetch("turn_id")
debug_export_download = Verification::ManualSupport.app_api_debug_export_conversation!(
  conversation_id: conversation_id,
  session_token: app_api_session_token,
  destination_path: debug_export_path
)
debug_payload = Verification::ManualSupport.extract_debug_export_payload!(
  debug_export_download.dig("download", "path")
)
workflow_run = debug_payload.fetch("workflow_runs")
  .select { |candidate| candidate.fetch("turn_id") == turn_id }
  .max_by { |candidate| [candidate.fetch("created_at").to_s, candidate.fetch("workflow_run_id")] } || {}
usage_event = debug_payload.fetch("usage_events")
  .find { |event| event.fetch("turn_id") == turn_id }
turn_record = Turn.find_by_public_id!(turn_id)

expected_dag_shape = ["turn_step"]
observed_dag_shape = debug_payload.fetch("workflow_nodes")
  .select { |node| node.fetch("turn_id") == turn_id }
  .sort_by { |node| [node.fetch("ordinal"), node.fetch("created_at").to_s] }
  .map { |node| node.fetch("node_key") }
expected_conversation_state = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "completed",
  "workflow_wait_state" => "ready",
  "turn_lifecycle_state" => "completed",
}
observed_conversation_state = {
  "conversation_state" => terminal.fetch("conversation").fetch("lifecycle_state"),
  "workflow_lifecycle_state" => workflow_run.fetch("lifecycle_state"),
  "workflow_wait_state" => workflow_run.fetch("wait_state"),
  "turn_lifecycle_state" => terminal.fetch("turn").fetch("lifecycle_state"),
}

result = Verification::ManualSupport.scenario_result(
  scenario: "workspace_agent_model_override_validation",
  expected_dag_shape: expected_dag_shape,
  observed_dag_shape: observed_dag_shape,
  expected_conversation_state: expected_conversation_state,
  observed_conversation_state: observed_conversation_state,
  proof_artifact_path: debug_export_path.to_s,
  extra: {
    "workspace_agent_id" => workspace_context.fetch(:workspace_agent).public_id,
    "settings_payload" => settings_payload.deep_stringify_keys,
    "resolved_model_selection_snapshot" => turn_record.resolved_model_selection_snapshot,
    "provider_handle" => usage_event&.fetch("provider_handle", nil),
    "model_ref" => usage_event&.fetch("model_ref", nil),
  }
)
result["passed"] &&=
  turn_record.resolved_model_selection_snapshot.fetch("normalized_selector", nil) == "role:mock" &&
  turn_record.resolved_model_selection_snapshot.fetch("resolved_provider_handle", nil) == "dev" &&
  turn_record.resolved_model_selection_snapshot.fetch("resolved_model_ref", nil) == "mock-model" &&
  usage_event&.fetch("provider_handle", nil) == "dev" &&
  usage_event&.fetch("model_ref", nil) == "mock-model"

Verification::ManualSupport.write_json(result)
