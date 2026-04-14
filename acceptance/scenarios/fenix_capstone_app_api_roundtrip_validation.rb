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
live_activity = nil
supervision_session = nil
live_activity_snapshots = []
supervision_probes = []
supervision_messages = nil
transcript_before = nil
transcript_after = nil
probe_questions = [
  "Please tell me what the 2048 work is doing right now and what changed most recently, if known.",
  "Please tell me what the 2048 work is doing right now and what part is currently in progress.",
  "Please tell me what the 2048 work is doing right now and the latest concrete step you can observe.",
  "Please tell me what the 2048 work is doing right now and whether anything is blocked or waiting.",
  "Please tell me what the 2048 work is doing right now and how it has progressed so far during this turn."
]
probe_interval_seconds = 1.0
probe_change_timeout_seconds = 8.0
probe_max_attempts = 3
probe_retry_delay_seconds = 1.0

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
    live_activity = Acceptance::ManualSupport.wait_for_app_api_turn_live_activity!(
      conversation_id: conversation_id,
      turn_id: turn_id,
      session_token: app_api_session_token
    ) do |turn:, runtime_events:, feed:|
      turn.fetch("provider_round_count", 0).to_i.positive? ||
        turn.fetch("tool_call_count", 0).to_i.positive? ||
        turn.fetch("command_run_count", 0).to_i.positive? ||
        turn.fetch("process_run_count", 0).to_i.positive? ||
        runtime_events.dig("summary", "event_count").to_i >= 3 ||
        Array(feed.fetch("items", [])).length >= 3
    end
    live_activity_snapshots << live_activity
    transcript_before = Acceptance::ManualSupport.app_api_conversation_transcript!(
      conversation_id: conversation_id,
      session_token: app_api_session_token
    )
    supervision_session = Acceptance::ManualSupport.app_api_create_conversation_supervision_session!(
      conversation_id: conversation_id,
      responder_strategy: "summary_model",
      session_token: app_api_session_token
    )
    probe_questions.each_with_index do |question, index|
      if index.positive?
        previous_metrics = Acceptance::ManualSupport.turn_live_activity_metrics(
          turn: live_activity.fetch("turn"),
          runtime_events: live_activity.fetch("runtime_events"),
          feed: live_activity.fetch("feed")
        )
        deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + probe_change_timeout_seconds

        loop do
          sleep(probe_interval_seconds)
          turns_payload = Acceptance::ManualSupport.app_api_conversation_diagnostics_turns!(
            conversation_id: conversation_id,
            session_token: app_api_session_token
          )
          turn_snapshot = turns_payload.fetch("items").find { |candidate| candidate.fetch("turn_id") == turn_id }
          raise "turn #{turn_id} was not visible while collecting live supervision probes" if turn_snapshot.nil?

          lifecycle_state = turn_snapshot.fetch("lifecycle_state")
          if %w[completed failed canceled].include?(lifecycle_state)
            raise "turn #{turn_id} reached terminal state before all live supervision probes were collected"
          end

          runtime_events = Acceptance::ManualSupport.app_api_conversation_turn_runtime_events!(
            conversation_id: conversation_id,
            turn_id: turn_id,
            session_token: app_api_session_token
          )
          feed_payload = Acceptance::ManualSupport.app_api_conversation_feed!(
            conversation_id: conversation_id,
            session_token: app_api_session_token
          )
          live_activity = {
            "turn" => turn_snapshot,
            "turns" => turns_payload.fetch("items"),
            "runtime_events" => runtime_events,
            "feed" => feed_payload,
          }

          current_metrics = Acceptance::ManualSupport.turn_live_activity_metrics(
            turn: turn_snapshot,
            runtime_events: runtime_events,
            feed: feed_payload
          )
          break if current_metrics != previous_metrics
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
        end

        live_activity_snapshots << live_activity
      end

      supervision_probes << Acceptance::ManualSupport.app_api_append_conversation_supervision_message_with_retry!(
        conversation_id: conversation_id,
        supervision_session_id: supervision_session.dig("conversation_supervision_session", "supervision_session_id"),
        content: question,
        session_token: app_api_session_token,
        max_attempts: probe_max_attempts,
        retry_delay_seconds: probe_retry_delay_seconds
      )
    end
    supervision_messages = Acceptance::ManualSupport.app_api_conversation_supervision_messages!(
      conversation_id: conversation_id,
      supervision_session_id: supervision_session.dig("conversation_supervision_session", "supervision_session_id"),
      session_token: app_api_session_token
    )
    transcript_after = Acceptance::ManualSupport.app_api_conversation_transcript!(
      conversation_id: conversation_id,
      session_token: app_api_session_token
    )
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
write_json(artifact_dir.join("evidence", "conversation-supervision-session.json"), supervision_session)
write_json(artifact_dir.join("evidence", "conversation-supervision-probes.json"), supervision_probes)
write_json(artifact_dir.join("evidence", "conversation-supervision-messages.json"), supervision_messages)
write_json(artifact_dir.join("evidence", "conversation-live-activity.json"), live_activity_snapshots)
write_json(artifact_dir.join("evidence", "runtime-validation.json"), runtime_validation)
write_json(artifact_dir.join("evidence", "conversation-debug-export-download.json"), debug_export_download)
write_json(artifact_dir.join("evidence", "conversation-export-download.json"), export_download)

Acceptance::CapstoneReviewArtifacts.install!(
  artifact_dir: artifact_dir,
  conversation_export_path: conversation_export_path,
  conversation_debug_export_path: conversation_debug_export_path,
  turn_feed: turn_feed,
  turn_runtime_events: turn_runtime_events,
  debug_payload: debug_payload
)

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
supervision_session_id = supervision_session.dig("conversation_supervision_session", "supervision_session_id")
export_supervision_messages = debug_payload.fetch("conversation_supervision_messages")
  .select { |message| message.fetch("supervision_session_id") == supervision_session_id }
message_roles = supervision_messages.fetch("items").map { |item| item.fetch("role") }
all_supervisor_transcript_responses = supervision_messages.fetch("items")
  .select { |item| item.fetch("role") == "supervisor_agent" }
  .map { |item| item.fetch("content") }
supervisor_responses = supervision_probes.map { |probe| probe.dig("human_sidechat", "content") }
transcript_before_ids = transcript_before.fetch("items").map { |item| item.fetch("id") }
transcript_after_ids = transcript_after.fetch("items").map { |item| item.fetch("id") }
live_activity_metrics = live_activity_snapshots.map do |snapshot|
  Acceptance::ManualSupport.turn_live_activity_metrics(
    turn: snapshot.fetch("turn"),
    runtime_events: snapshot.fetch("runtime_events"),
    feed: snapshot.fetch("feed")
  )
end
metrics_changed_rounds = live_activity_metrics.each_cons(2).count do |previous_metrics, current_metrics|
  previous_metrics != current_metrics
end
progress_dimensions = %w[
  provider_round_count
  tool_call_count
  command_run_count
  process_run_count
  runtime_event_count
  feed_item_count
]
progress_dimensions_advanced = progress_dimensions.select do |key|
  live_activity_metrics.last.fetch(key) > live_activity_metrics.first.fetch(key)
end
progress_signal_count = supervisor_responses.count do |content|
  content.match?(/most recent|recent change|recently|progress|completed|created|started|finished|next step|blocked|waiting|working through|in progress/i)
end
refusal_or_apology_leak = supervisor_responses.any? do |content|
  content.match?(/I.?m sorry/i) || content.match?(/cannot assist/i)
end
transcript_refusal_or_apology_leak = all_supervisor_transcript_responses.any? do |content|
  content.match?(/I.?m sorry/i) || content.match?(/cannot assist/i)
end
game_work_reference_count = supervisor_responses.count do |content|
  content.match?(/2048|game|board|tile|move|project|app/i)
end
live_wording_present = supervisor_responses.all? { |content| content.match?(/right now|currently/i) }
completion_leak = supervisor_responses.any? { |content| content.match?(/execution runtime completed|turn completed/i) }
minimum_message_count = probe_questions.length * 2
alternating_roles = message_roles.each_slice(2).all? { |pair| pair == %w[user supervisor_agent] }
all_probes_accepted = supervision_probes.all? { |probe| probe.fetch("accepted_attempt").present? }
retry_round_count = supervision_probes.count { |probe| probe.fetch("accepted_attempt").to_i > 1 }
total_retry_attempts = supervision_probes.sum { |probe| probe.fetch("retry_attempts").length } - supervision_probes.length
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
  conversation_export_path.exist? &&
  live_activity_snapshots.length == probe_questions.length &&
  live_activity_snapshots.none? do |snapshot|
    %w[completed failed canceled].include?(snapshot.fetch("turn").fetch("lifecycle_state"))
  end &&
  live_activity_snapshots.any? { |snapshot| snapshot.fetch("turn").fetch("lifecycle_state") == "active" } &&
  live_activity_snapshots.all? do |snapshot|
    Acceptance::ManualSupport.runtime_activity_present?(snapshot.fetch("runtime_events")) ||
      Acceptance::ManualSupport.feed_activity_present?(snapshot.fetch("feed"))
  end &&
  all_probes_accepted &&
  metrics_changed_rounds >= 2 &&
  progress_dimensions_advanced.length >= 2 &&
  live_wording_present &&
  game_work_reference_count >= 4 &&
  progress_signal_count >= 3 &&
  !refusal_or_apology_leak &&
  !completion_leak &&
  transcript_before_ids == transcript_after_ids &&
  supervision_messages.fetch("items").length >= minimum_message_count &&
  export_supervision_messages.length == supervision_messages.fetch("items").length &&
  alternating_roles &&
  export_supervision_messages.map { |message| message.fetch("role") } == message_roles &&
  supervisor_responses.uniq.length >= 4

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
    - conversation debug export path: `#{conversation_debug_export_path}`
    - generated app dir: `#{generated_app_dir}`
    - review index: `#{artifact_dir.join("review", "index.md")}`
    - conversation transcript review: `#{artifact_dir.join("review", "conversation-transcript.md")}`
    - diagnostics summary review: `#{artifact_dir.join("review", "diagnostics-summary.md")}`
    - runtime events review: `#{artifact_dir.join("review", "runtime-events.md")}`
    - supervision feed review: `#{artifact_dir.join("review", "supervision-feed.md")}`
    - supervision sidechat review: `#{artifact_dir.join("review", "supervision-sidechat.md")}`
    - live sidechat rounds while turn in progress: `#{live_activity_snapshots.length}`
    - accepted live sidechat rounds: `#{supervision_probes.length}`
    - live sidechat metric-changing transitions: `#{metrics_changed_rounds}`
    - live sidechat progress dimensions advanced: `#{progress_dimensions_advanced.join(", ")}`
    - live sidechat retry rounds: `#{retry_round_count}`
    - live sidechat extra retry attempts: `#{total_retry_attempts}`
    - sidechat responses grounded in game/project work: `#{game_work_reference_count}`
    - sidechat responses with progress semantics: `#{progress_signal_count}`
    - accepted sidechat refusal or apology leak: `#{refusal_or_apology_leak}`
    - transcript sidechat refusal or apology leak: `#{transcript_refusal_or_apology_leak}`
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
    "live_activity" => live_activity_snapshots,
    "live_activity_metrics" => live_activity_metrics,
    "live_activity_metrics_changed_rounds" => metrics_changed_rounds,
    "live_activity_progress_dimensions_advanced" => progress_dimensions_advanced,
    "supervision_session_id" => supervision_session_id,
    "supervision_probe_questions" => probe_questions,
    "supervision_probe_contents" => supervisor_responses,
    "supervision_probe_retry_round_count" => retry_round_count,
    "supervision_probe_extra_retry_attempts" => total_retry_attempts,
    "supervision_game_work_reference_count" => game_work_reference_count,
    "supervision_progress_signal_count" => progress_signal_count,
    "supervision_refusal_or_apology_leak" => refusal_or_apology_leak,
    "supervision_transcript_refusal_or_apology_leak" => transcript_refusal_or_apology_leak,
    "supervision_message_roles" => message_roles,
    "transcript_before_ids" => transcript_before_ids,
    "transcript_after_ids" => transcript_after_ids,
  }
)
result["passed"] = passed

Acceptance::ManualSupport.write_json(result)

unless result.fetch("passed")
  raise "2048 capstone acceptance failed; see #{artifact_dir}"
end
