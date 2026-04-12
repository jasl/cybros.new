#!/usr/bin/env ruby
# ACCEPTANCE_MODE: app_api_surface
# This scenario must validate the end-user conversation flow through app_api only.

require_relative "../lib/boot"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
fingerprint = "acceptance-provider-backed-runtime"
selector = ENV.fetch("PHASE2_PROVIDER_SELECTOR", "candidate:openrouter/openai-gpt-5.4")
artifact_stamp = ENV.fetch("PROVIDER_BACKED_TURN_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-provider-backed-turn-validation"
end
artifact_dir = AcceptanceHarness.repo_root.join("acceptance", "artifacts", artifact_stamp)
debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")
content = ENV.fetch(
  "PHASE2_PROVIDER_PROMPT",
  "Reply with ACCEPTED-PHASE2 exactly. Do not add any other words or punctuation."
)

Acceptance::ManualSupport.reset_backend_state!
bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!
app_api_session_token = Acceptance::ManualSupport.issue_app_api_session_token!(user: bootstrap.user)
bundled = Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  execution_runtime_fingerprint: "acceptance-provider-backed-environment",
  fingerprint: fingerprint
)
FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)
created = nil
terminal = nil

Acceptance::ManualSupport.with_fenix_control_worker_for_registration!(registration: bundled) do
  created = Acceptance::ManualSupport.app_api_create_conversation!(
    agent_id: bundled.agent_definition_version.agent.public_id,
    content: content,
    selector: selector,
    session_token: app_api_session_token
  )
  terminal = Acceptance::ManualSupport.wait_for_app_api_turn_terminal!(
    conversation_id: created.dig("conversation", "conversation_id"),
    turn_id: created.fetch("turn_id"),
    session_token: app_api_session_token
  )
end

conversation_id = created.dig("conversation", "conversation_id")
turn_id = created.fetch("turn_id")
debug_export_download = Acceptance::ManualSupport.app_api_debug_export_conversation!(
  conversation_id: conversation_id,
  session_token: app_api_session_token,
  destination_path: debug_export_path
)
debug_payload = Acceptance::ManualSupport.extract_debug_export_payload!(
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

Acceptance::ManualSupport.write_json(
  Acceptance::ManualSupport.scenario_result(
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
