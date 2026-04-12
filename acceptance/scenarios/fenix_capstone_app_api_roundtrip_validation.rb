#!/usr/bin/env ruby

require "date"
require "fileutils"
require "json"
require "pathname"
require_relative "../lib/boot"
require_relative "../lib/capstone_app_api_roundtrip"
require_relative "../lib/host_validation"

agent_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
runtime_base_url = ENV.fetch("NEXUS_RUNTIME_BASE_URL", "http://127.0.0.1:3301")
selector = ENV.fetch("CAPSTONE_SELECTOR", "candidate:openrouter/openai-gpt-5.4")
preview_port = Integer(ENV.fetch("CAPSTONE_HOST_PREVIEW_PORT", "4274"))
scenario_date = Date.current.iso8601

repo_root = AcceptanceHarness.repo_root
artifact_stamp = ENV.fetch("CAPSTONE_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-core-matrix-loop-fenix-2048-final"
end
artifact_dir = repo_root.join("acceptance", "artifacts", artifact_stamp)
workspace_root = Pathname.new(ENV.fetch("CAPSTONE_WORKSPACE_ROOT", repo_root.join("tmp", "fenix").to_s)).expand_path
generated_app_dir = workspace_root.join("game-2048")
conversation_export_path = artifact_dir.join("exports", "conversation-export.zip")
conversation_debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")
prompt = Acceptance::CapstoneAppApiRoundtrip.prompt(generated_app_dir: generated_app_dir.to_s)

def write_json(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload) + "\n")
end

def write_text(path, contents)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, contents)
end

unless ActiveModel::Type::Boolean.new.cast(ENV["CAPSTONE_SKIP_BACKEND_RESET"])
  Acceptance::ManualSupport.reset_backend_state!
end

FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)
FileUtils.rm_rf(generated_app_dir)

bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!
app_api_session_token = Acceptance::ManualSupport.issue_app_api_session_token!(user: bootstrap.user)
bundled_registration = Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: agent_base_url,
  execution_runtime_fingerprint: "acceptance-capstone-bundled-fenix-environment",
  fingerprint: "acceptance-capstone-bundled-fenix-runtime"
)
onboarding = Acceptance::ManualSupport.app_api_admin_create_onboarding_session!(
  target_kind: "execution_runtime",
  session_token: app_api_session_token
)
bring_your_own_runtime_registration = Acceptance::ManualSupport.register_bring_your_own_execution_runtime!(
  onboarding_token: onboarding.fetch("onboarding_token"),
  runtime_base_url: runtime_base_url,
  execution_runtime_fingerprint: "acceptance-capstone-bring-your-own-runtime-environment"
)

write_json(
  artifact_dir.join("evidence", "acceptance-registration.json"),
  Acceptance::CapstoneAppApiRoundtrip.registration_artifact(
    agent_definition_version: bundled_registration.agent_definition_version,
    execution_runtime: bring_your_own_runtime_registration.fetch(:execution_runtime),
    agent_connection_credential: bundled_registration.agent_connection_credential,
    onboarding_session_id: onboarding.dig("onboarding_session", "onboarding_session_id")
  ).merge(
    "agent_connection_id" => bundled_registration.agent_connection_id,
    "execution_runtime_connection_id" => bring_your_own_runtime_registration.fetch(:execution_runtime_connection_id)
  )
)
write_json(
  artifact_dir.join("evidence", "capstone-run-bootstrap.json"),
  Acceptance::CapstoneAppApiRoundtrip.run_bootstrap_artifact(
    scenario_date: scenario_date,
    selector: selector,
    workspace_root: workspace_root,
    generated_app_dir: generated_app_dir,
    prompt: prompt
  )
)

created = nil
conversation_id = nil
turn_id = nil
terminal = nil
turn_runtime_events = nil
turn_feed = nil

Acceptance::ManualSupport.with_fenix_control_worker!(
  agent_connection_credential: bundled_registration.agent_connection_credential,
  execution_runtime_connection_credential: bring_your_own_runtime_registration.fetch(:execution_runtime_connection_credential),
  limit: 10,
  inline: true
) do
  Acceptance::ManualSupport.with_nexus_control_worker!(
    execution_runtime_connection_credential: bring_your_own_runtime_registration.fetch(:execution_runtime_connection_credential),
    limit: 10,
    inline: true
  ) do
    created = Acceptance::ManualSupport.app_api_create_conversation!(
      agent_id: bundled_registration.agent_definition_version.agent.public_id,
      content: prompt,
      selector: selector,
      session_token: app_api_session_token,
      execution_runtime_id: bring_your_own_runtime_registration.fetch(:execution_runtime).public_id
    )
    conversation_id = created.dig("conversation", "conversation_id")
    turn_id = created.fetch("turn_id")
    terminal = Acceptance::ManualSupport.wait_for_app_api_turn_terminal!(
      conversation_id: conversation_id,
      turn_id: turn_id,
      session_token: app_api_session_token
    )
    turn_runtime_events = Acceptance::ManualSupport.app_api_conversation_turn_runtime_events!(
      conversation_id: conversation_id,
      turn_id: turn_id,
      session_token: app_api_session_token
    )
    turn_feed = Acceptance::ManualSupport.app_api_conversation_feed!(
      conversation_id: conversation_id,
      session_token: app_api_session_token
    )
  end
end

debug_export_download = Acceptance::ManualSupport.app_api_debug_export_conversation!(
  conversation_id: conversation_id,
  session_token: app_api_session_token,
  destination_path: conversation_debug_export_path
)
debug_payload = Acceptance::ManualSupport.extract_debug_export_payload!(
  debug_export_download.dig("download", "path")
)
runtime_validation = ManualAcceptance::ConversationRuntimeValidation.build(
  tool_invocations: debug_payload.fetch("tool_invocations")
)
runtime_mentions_2048 = runtime_validation.fetch("runtime_browser_content_excerpt").match?(/\b2048\b/i)
host_validation_bundle = Acceptance::HostValidation.run!(
  generated_app_dir: generated_app_dir,
  artifact_dir: artifact_dir,
  preview_port: preview_port,
  runtime_validation: runtime_validation,
  persist_artifacts: true
)
host_validation = host_validation_bundle.fetch("host_validation")
playwright_validation = host_validation_bundle.fetch("playwright_validation")
export_download = Acceptance::ManualSupport.app_api_export_conversation!(
  conversation_id: conversation_id,
  session_token: app_api_session_token,
  destination_path: conversation_export_path
)

write_json(artifact_dir.join("evidence", "conversation-debug-export.json"), debug_payload)
write_json(artifact_dir.join("evidence", "conversation-turn-runtime-events.json"), turn_runtime_events)
write_json(artifact_dir.join("evidence", "conversation-turn-feed.json"), turn_feed)
write_json(artifact_dir.join("evidence", "runtime-validation.json"), runtime_validation)
write_json(artifact_dir.join("evidence", "conversation-debug-export-download.json"), debug_export_download)
write_json(artifact_dir.join("evidence", "conversation-export-download.json"), export_download)

observed_dag_shape = debug_payload.fetch("workflow_nodes")
  .select { |node| node.fetch("turn_id") == turn_id }
  .sort_by { |node| [node.fetch("ordinal"), node.fetch("created_at").to_s] }
  .map { |node| node.fetch("node_key") }
expected_dag_shape = [
  "turn_step",
  "provider_round_*_tool_*",
  "provider_round_*_join_*"
]
dag_shape_passed =
  observed_dag_shape.first == "turn_step" &&
  observed_dag_shape.any? { |key| key.match?(/\Aprovider_round_\d+_tool_\d+\z/) } &&
  observed_dag_shape.any? { |key| key.match?(/\Aprovider_round_\d+_join_\d+\z/) }
expected_conversation_state = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "completed",
  "workflow_wait_state" => "ready",
  "turn_lifecycle_state" => "completed",
}
workflow_run = debug_payload.fetch("workflow_runs")
  .select { |candidate| candidate.fetch("turn_id") == turn_id }
  .max_by { |candidate| [candidate.fetch("created_at").to_s, candidate.fetch("workflow_run_id")] } || {}
selected_output_message = debug_payload.fetch("conversation_payload")
  .fetch("messages")
  .reverse
  .find { |message| message.fetch("turn_public_id") == turn_id && message.fetch("role") == "assistant" }
observed_conversation_state = {
  "conversation_state" => terminal.fetch("conversation").fetch("lifecycle_state"),
  "workflow_lifecycle_state" => workflow_run.fetch("lifecycle_state"),
  "workflow_wait_state" => workflow_run.fetch("wait_state"),
  "turn_lifecycle_state" => terminal.fetch("turn").fetch("lifecycle_state"),
  "selected_output_message_id" => selected_output_message&.fetch("message_public_id", nil),
  "selected_output_content" => selected_output_message&.fetch("content", nil),
}.compact

passed = dag_shape_passed &&
  expected_conversation_state.all? { |key, value| observed_conversation_state[key] == value } &&
  Acceptance::HostValidation.runtime_validation_passed?(runtime_validation) &&
  runtime_mentions_2048 &&
  Acceptance::HostValidation.host_validation_passed?(
    host_validation: host_validation,
    playwright_validation: playwright_validation
  ) &&
  conversation_export_path.exist?

write_text(
  artifact_dir.join("review", "summary.md"),
  <<~MD
    # 2048 Capstone Summary

    - passed: `#{passed}`
    - agent base url: `#{agent_base_url}`
    - runtime base url: `#{runtime_base_url}`
    - selector: `#{selector}`
    - dag shape passed: `#{dag_shape_passed}`
    - runtime validation passed: `#{Acceptance::HostValidation.runtime_validation_passed?(runtime_validation)}`
    - runtime browser mentioned 2048: `#{runtime_mentions_2048}`
    - host validation passed: `#{Acceptance::HostValidation.host_validation_passed?(host_validation: host_validation, playwright_validation: playwright_validation)}`
    - conversation export path: `#{conversation_export_path}`
    - generated app dir: `#{generated_app_dir}`
  MD
)

result = Acceptance::ManualSupport.scenario_result(
  scenario: "fenix_capstone_app_api_roundtrip_validation",
  expected_dag_shape: expected_dag_shape,
  observed_dag_shape: observed_dag_shape,
  expected_conversation_state: expected_conversation_state,
  observed_conversation_state: observed_conversation_state,
  proof_artifact_path: artifact_dir.to_s,
  extra: {
    "agent_base_url" => agent_base_url,
    "runtime_base_url" => runtime_base_url,
    "onboarding_session_id" => onboarding.dig("onboarding_session", "onboarding_session_id"),
    "agent_definition_version_id" => bundled_registration.agent_definition_version.public_id,
    "execution_runtime_id" => bring_your_own_runtime_registration.fetch(:execution_runtime).public_id,
    "execution_runtime_version_id" => bring_your_own_runtime_registration.fetch(:execution_runtime_version).public_id,
    "conversation_id" => conversation_id,
    "turn_id" => turn_id,
    "workflow_run_id" => workflow_run.fetch("workflow_run_id", nil),
    "dag_shape_passed" => dag_shape_passed,
    "runtime_validation" => runtime_validation,
    "runtime_browser_mentions_2048" => runtime_mentions_2048,
    "host_validation" => host_validation,
    "playwright_validation" => playwright_validation,
    "conversation_export_path" => conversation_export_path.to_s,
    "conversation_debug_export_path" => conversation_debug_export_path.to_s,
    "selected_output_message_id" => selected_output_message&.fetch("message_public_id", nil),
    "selected_output_content" => selected_output_message&.fetch("content", nil),
  }
)
result["passed"] = passed

Acceptance::ManualSupport.write_json(result)

unless result.fetch("passed")
  raise "2048 capstone acceptance failed; see #{artifact_dir}"
end
