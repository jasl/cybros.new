#!/usr/bin/env ruby
# VERIFICATION_MODE: app_api_surface
# This scenario must validate the end-user conversation flow through app_api only.

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "verification/hosted/core_matrix"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
fingerprint = "verification-provider-backed-runtime"
selector = ENV.fetch("PHASE2_PROVIDER_SELECTOR", "role:main")
artifact_stamp = ENV.fetch("PROVIDER_BACKED_TURN_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-provider-backed-turn-validation"
end
artifact_dir = Verification.repo_root.join("verification", "artifacts", artifact_stamp)
debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")
content = ENV.fetch(
  "PHASE2_PROVIDER_PROMPT",
  "Reply with ACCEPTED-PHASE2 exactly. Do not add any other words or punctuation."
)

Verification::ManualSupport.reset_backend_state!
bootstrap = Verification::ManualSupport.bootstrap_and_seed!
app_api_session_token = Verification::ManualSupport.issue_app_api_session_token!(user: bootstrap.user)
bundled = Verification::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  execution_runtime_fingerprint: "verification-provider-backed-environment",
  fingerprint: fingerprint
)
workspace_context = Verification::ManualSupport.enable_default_workspace!(
  agent_definition_version: bundled.agent_definition_version
)
FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)
created = nil
terminal = nil

Verification::ManualSupport.with_fenix_control_worker_for_registration!(registration: bundled) do
  created = Verification::ManualSupport.app_api_create_conversation!(
    workspace_agent_id: workspace_context.fetch(:workspace_agent).public_id,
    content: content,
    selector: selector,
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
selected_output_message = debug_payload.fetch("conversation_payload")
  .fetch("messages")
  .reverse
  .find { |message| message.fetch("turn_public_id") == turn_id && message.fetch("role") == "assistant" }
usage_event = debug_payload.fetch("usage_events")
  .find { |event| event.fetch("turn_id") == turn_id }

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
  "selected_output_message_id" => selected_output_message&.fetch("message_public_id", nil),
  "selected_output_content" => selected_output_message&.fetch("content", nil),
}.compact

Verification::ManualSupport.write_json(
  Verification::ManualSupport.scenario_result(
    scenario: "provider_backed_turn_validation",
    expected_dag_shape: expected_dag_shape,
    observed_dag_shape: observed_dag_shape,
    expected_conversation_state: expected_conversation_state,
    observed_conversation_state: observed_conversation_state,
    extra: {
      "agent_definition_version_id" => bundled.agent_definition_version.public_id,
      "execution_runtime_id" => bundled.execution_runtime.public_id,
      "conversation_id" => conversation_id,
      "turn_id" => turn_id,
      "workflow_run_id" => workflow_run.fetch("workflow_run_id", nil),
      "provider_handle" => usage_event&.fetch("provider_handle", nil),
      "model_ref" => usage_event&.fetch("model_ref", nil),
      "selector" => selector,
      "debug_export_path" => debug_export_path.to_s,
    }
  )
)
