#!/usr/bin/env ruby

require "date"
require "digest"
require "fileutils"
require "json"
require "pathname"
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "verification/hosted/core_matrix"
require "verification/suites/proof/capstone_app_api_roundtrip"
require "verification/support/host_validation"

agent_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
runtime_base_url = ENV.fetch("NEXUS_RUNTIME_BASE_URL", "http://127.0.0.1:3301")
selector = ENV.fetch("CAPSTONE_SELECTOR", "role:main")
preview_port = Integer(ENV.fetch("CAPSTONE_HOST_PREVIEW_PORT", "4274"))
scenario_date = Date.current.iso8601

repo_root = Verification.repo_root
artifact_stamp = ENV.fetch("CAPSTONE_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-core-matrix-loop-fenix-2048-final"
end
artifact_dir = repo_root.join("verification", "artifacts", artifact_stamp)
workspace_root = Pathname.new(ENV.fetch("CAPSTONE_WORKSPACE_ROOT", repo_root.join("tmp", "fenix").to_s)).expand_path
generated_app_dir = workspace_root.join("game-2048")
conversation_export_path = artifact_dir.join("exports", "conversation-export.zip")
conversation_debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")
published_attachment_upload_path = artifact_dir.join("uploads", "game-2048-dist.zip")
published_attachment_download_path = artifact_dir.join("downloads", "published-primary-deliverable.zip")
published_attachment_extract_dir = artifact_dir.join("downloads", "published-primary-deliverable")
prompt = Verification::CapstoneAppApiRoundtrip.prompt(generated_app_dir: generated_app_dir.to_s)

def write_json(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload) + "\n")
end

def write_text(path, contents)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, contents)
end

def zip_entry_names(zip_path)
  Zip::File.open(zip_path.to_s) { |zip| zip.entries.map(&:name).sort }
end

def read_zip_json(zip_path, entry_name)
  Zip::File.open(zip_path.to_s) do |zip|
    entry = zip.find_entry(entry_name)
    raise "missing #{entry_name} in #{zip_path}" if entry.nil?

    JSON.parse(entry.get_input_stream.read)
  end
end

def build_zip_from_directory(source_dir:, archive_path:, root_prefix:)
  source_dir = Pathname.new(source_dir)
  archive_path = Pathname.new(archive_path)
  raise "missing source directory #{source_dir}" unless source_dir.directory?

  FileUtils.mkdir_p(archive_path.dirname)

  Zip::OutputStream.open(archive_path.to_s) { }
  Zip::File.open(archive_path.to_s, create: true) do |zip|
    Dir.chdir(source_dir.to_s) do
      Dir.glob("**/*", File::FNM_DOTMATCH).sort.each do |relative_path|
        next if relative_path == "." || relative_path == ".."

        absolute_path = source_dir.join(relative_path)
        entry_name = [root_prefix, relative_path].join("/")

        if absolute_path.directory?
          zip.mkdir(entry_name) unless zip.find_entry(entry_name)
          next
        end

        zip.get_output_stream(entry_name) do |stream|
          File.open(absolute_path.to_s, "rb") do |file|
            IO.copy_stream(file, stream)
          end
        end
      end
    end
  end
end

def read_zip_entry(zip_path, entry_name)
  Zip::File.open(zip_path.to_s) do |zip|
    entry = zip.find_entry(entry_name)
    raise "missing #{entry_name} in #{zip_path}" if entry.nil?

    entry.get_input_stream.read
  end
end

def sha256_for_file(path)
  Digest::SHA256.file(path.to_s).hexdigest
end

def sha256_for_bytes(bytes)
  Digest::SHA256.hexdigest(bytes)
end

def unzip_to_directory(zip_path, destination_dir)
  FileUtils.rm_rf(destination_dir)
  FileUtils.mkdir_p(destination_dir)

  Zip::File.open(zip_path.to_s) do |zip|
    zip.each do |entry|
      raise "unsafe zip entry #{entry.name}" if entry.name.start_with?("/", "../") || entry.name.include?("/../")

      destination_path = Pathname.new(destination_dir).join(entry.name)

      if entry.directory?
        FileUtils.mkdir_p(destination_path)
        next
      end

      FileUtils.mkdir_p(destination_path.dirname)
      entry.get_input_stream do |stream|
        File.open(destination_path.to_s, "wb") do |file|
          IO.copy_stream(stream, file)
        end
      end
    end
  end
end

unless ActiveModel::Type::Boolean.new.cast(ENV["CAPSTONE_SKIP_BACKEND_RESET"])
  Verification::ManualSupport.reset_backend_state!
end

FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)
FileUtils.rm_rf(generated_app_dir)

cli_init_bootstrap = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "init-bootstrap",
  args: ["init"],
  input: [
    Verification::ManualSupport::CONTROL_BASE_URL,
    "Primary Installation",
    "admin@example.com",
    "Password123!",
    "Password123!",
    "Primary Admin",
  ].join("\n") + "\n"
)
app_api_session_token = cli_init_bootstrap.fetch("credentials").fetch("session_token")

Verification::ManualSupport.silence_stdout do
  load Rails.root.join("db/seeds.rb")
end

installation = Installation.order(:id).last || raise("expected CLI bootstrap to create an installation")
bundled_registration = Verification::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: installation,
  runtime_base_url: agent_base_url,
  execution_runtime_fingerprint: "verification-capstone-bundled-fenix-environment",
  fingerprint: "verification-capstone-bundled-fenix-runtime"
)
cli_init_refresh = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "init-refresh",
  args: ["init"]
)
cli_workspace_create = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "workspace-create",
  args: ["workspace", "create", "--name", "Capstone Workspace", "--default"]
)
selected_workspace_id = cli_workspace_create.fetch("config").fetch("workspace_id")
cli_workspace_use = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "workspace-use",
  args: ["workspace", "use", selected_workspace_id]
)
cli_agent_attach = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "agent-attach",
  args: ["agent", "attach", "--workspace-id", selected_workspace_id, "--agent-id", bundled_registration.agent.public_id]
)
cli_status = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "status",
  args: ["status"]
)
workspace_context = {
  workspace: Workspace.find_by_public_id!(cli_status.fetch("config").fetch("workspace_id")),
  workspace_agent: WorkspaceAgent.find_by_public_id!(cli_status.fetch("config").fetch("workspace_agent_id")),
}
onboarding = Verification::ManualSupport.app_api_admin_create_onboarding_session!(
  target_kind: "execution_runtime",
  session_token: app_api_session_token
)
bring_your_own_runtime_registration = Verification::ManualSupport.register_bring_your_own_execution_runtime!(
  onboarding_token: onboarding.fetch("onboarding_token"),
  runtime_base_url: runtime_base_url,
  execution_runtime_fingerprint: "verification-capstone-bring-your-own-runtime-environment"
)

write_json(
  artifact_dir.join("evidence", "verification-registration.json"),
  Verification::CapstoneAppApiRoundtrip.registration_artifact(
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
  Verification::CapstoneAppApiRoundtrip.run_bootstrap_artifact(
    scenario_date: scenario_date,
    selector: selector,
    workspace_root: workspace_root,
    generated_app_dir: generated_app_dir,
    prompt: prompt
  )
)
write_json(
  artifact_dir.join("evidence", "cli-setup.json"),
  {
    "init_bootstrap" => cli_init_bootstrap,
    "init_refresh" => cli_init_refresh,
    "workspace_create" => cli_workspace_create,
    "workspace_use" => cli_workspace_use,
    "agent_attach" => cli_agent_attach,
    "status" => cli_status,
  }
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
output_message = nil
published_attachment_create = nil
published_attachment = nil
published_attachment_show = nil
published_attachment_download = nil
published_attachment_entry_names = []
published_attachment_upload_sha256 = nil
published_attachment_download_sha256 = nil
published_attachment_export_sha256 = nil
published_attachment_upload_byte_size = nil
published_attachment_export_bytes = nil
published_export_payload = nil
published_export_entry_names = []
probe_questions = [
  "Please tell me what the 2048 work is doing right now and what changed most recently, if known.",
  "Please tell me what the 2048 work is doing right now and what part is currently in progress.",
  "Please tell me what the 2048 work is doing right now and the latest concrete step you can observe.",
  "Please tell me what the 2048 work is doing right now and whether anything is blocked or waiting.",
  "Please tell me what the 2048 work is doing right now and how it has progressed so far during this turn."
]
turn_completed_before_all_live_probes = false
probe_interval_seconds = 1.0
probe_change_timeout_seconds = 8.0
probe_max_attempts = 3
probe_retry_delay_seconds = 1.0

Verification::ManualSupport.with_fenix_control_worker!(
  agent_connection_credential: bundled_registration.agent_connection_credential,
  execution_runtime_connection_credential: bring_your_own_runtime_registration.fetch(:execution_runtime_connection_credential),
  limit: 10,
  inline: true
) do
  Verification::ManualSupport.with_nexus_control_worker!(
    execution_runtime_connection_credential: bring_your_own_runtime_registration.fetch(:execution_runtime_connection_credential),
    limit: 10,
    inline: true
  ) do
    created = Verification::ManualSupport.app_api_create_conversation!(
      workspace_agent_id: workspace_context.fetch(:workspace_agent).public_id,
      content: prompt,
      selector: selector,
      session_token: app_api_session_token,
      execution_runtime_id: bring_your_own_runtime_registration.fetch(:execution_runtime).public_id
    )
    conversation_id = created.dig("conversation", "conversation_id")
    turn_id = created.fetch("turn_id")
    live_activity = Verification::ManualSupport.wait_for_app_api_turn_live_activity!(
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
    transcript_before = Verification::ManualSupport.app_api_conversation_transcript!(
      conversation_id: conversation_id,
      session_token: app_api_session_token
    )
    supervision_session = Verification::ManualSupport.app_api_create_conversation_supervision_session!(
      conversation_id: conversation_id,
      responder_strategy: "hybrid",
      session_token: app_api_session_token
    )
    probe_questions.each_with_index do |question, index|
      if index.positive?
        previous_metrics = Verification::ManualSupport.turn_live_activity_metrics(
          turn: live_activity.fetch("turn"),
          runtime_events: live_activity.fetch("runtime_events"),
          feed: live_activity.fetch("feed")
        )
        deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + probe_change_timeout_seconds

        loop do
          sleep(probe_interval_seconds)
          turns_payload = Verification::ManualSupport.app_api_conversation_diagnostics_turns!(
            conversation_id: conversation_id,
            session_token: app_api_session_token
          )
          turn_snapshot = turns_payload.fetch("items").find { |candidate| candidate.fetch("turn_id") == turn_id }
          raise "turn #{turn_id} was not visible while collecting live supervision probes" if turn_snapshot.nil?

          lifecycle_state = turn_snapshot.fetch("lifecycle_state")
          if %w[completed failed canceled].include?(lifecycle_state)
            turn_completed_before_all_live_probes = true
            break
          end

          runtime_events = Verification::ManualSupport.app_api_conversation_turn_runtime_events!(
            conversation_id: conversation_id,
            turn_id: turn_id,
            session_token: app_api_session_token
          )
          feed_payload = Verification::ManualSupport.app_api_conversation_feed!(
            conversation_id: conversation_id,
            session_token: app_api_session_token
          )
          live_activity = {
            "turn" => turn_snapshot,
            "turns" => turns_payload.fetch("items"),
            "runtime_events" => runtime_events,
            "feed" => feed_payload,
          }

          current_metrics = Verification::ManualSupport.turn_live_activity_metrics(
            turn: turn_snapshot,
            runtime_events: runtime_events,
            feed: feed_payload
          )
          break if current_metrics != previous_metrics
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
        end

        break if turn_completed_before_all_live_probes

        live_activity_snapshots << live_activity
      end

      supervision_probes << Verification::ManualSupport.app_api_append_conversation_supervision_message_with_retry!(
        conversation_id: conversation_id,
        supervision_session_id: supervision_session.dig("conversation_supervision_session", "supervision_session_id"),
        content: question,
        session_token: app_api_session_token,
        max_attempts: probe_max_attempts,
        retry_delay_seconds: probe_retry_delay_seconds
      )
    end
    supervision_messages = Verification::ManualSupport.app_api_conversation_supervision_messages!(
      conversation_id: conversation_id,
      supervision_session_id: supervision_session.dig("conversation_supervision_session", "supervision_session_id"),
      session_token: app_api_session_token
    )
    transcript_after = Verification::ManualSupport.app_api_conversation_transcript!(
      conversation_id: conversation_id,
      session_token: app_api_session_token
    )
    terminal = Verification::ManualSupport.wait_for_app_api_turn_terminal!(
      conversation_id: conversation_id,
      turn_id: turn_id,
      session_token: app_api_session_token
    )
    turn_runtime_events = Verification::ManualSupport.app_api_conversation_turn_runtime_events!(
      conversation_id: conversation_id,
      turn_id: turn_id,
      session_token: app_api_session_token
    )
    turn_feed = Verification::ManualSupport.app_api_conversation_feed!(
      conversation_id: conversation_id,
      session_token: app_api_session_token
    )
  end
end

output_message = Turn.find_by_public_id!(turn_id).selected_output_message || raise("selected output message missing for turn #{turn_id}")
build_zip_from_directory(
  source_dir: generated_app_dir.join("dist"),
  archive_path: published_attachment_upload_path,
  root_prefix: "dist"
)
published_attachment_upload_sha256 = sha256_for_file(published_attachment_upload_path)
published_attachment_upload_byte_size = File.size(published_attachment_upload_path)
published_attachment_create = Verification::ManualSupport.execution_runtime_publish_output_attachment!(
  turn_id: turn_id,
  file_path: published_attachment_upload_path,
  execution_runtime_connection_credential: bring_your_own_runtime_registration.fetch(:execution_runtime_connection_credential),
  publication_role: "primary_deliverable",
)
published_attachment = published_attachment_create.fetch("attachments").fetch(0)
published_attachment_show = Verification::ManualSupport.app_api_conversation_attachment_show!(
  conversation_id: conversation_id,
  attachment_id: published_attachment.fetch("attachment_id"),
  session_token: app_api_session_token
)
published_attachment_download = Verification::ManualSupport.download_public_url!(
  url: published_attachment_show.dig("attachment", "download_url"),
  destination_path: published_attachment_download_path
)
published_attachment_download_sha256 = sha256_for_file(published_attachment_download.fetch("path"))
published_attachment_entry_names = zip_entry_names(published_attachment_download.fetch("path"))
unzip_to_directory(published_attachment_download.fetch("path"), published_attachment_extract_dir)
debug_export_download = Verification::ManualSupport.app_api_debug_export_conversation!(
  conversation_id: conversation_id,
  session_token: app_api_session_token,
  destination_path: conversation_debug_export_path
)
debug_payload = Verification::ManualSupport.extract_debug_export_payload!(
  debug_export_download.dig("download", "path")
)
runtime_validation = Verification::ConversationRuntimeValidation.build(
  tool_invocations: debug_payload.fetch("tool_invocations")
)
runtime_mentions_2048 = runtime_validation.fetch("runtime_browser_content_excerpt").match?(/\b2048\b/i)
host_validation_bundle = Verification::HostValidation.run!(
  generated_app_dir: generated_app_dir,
  artifact_dir: artifact_dir,
  preview_port: preview_port,
  runtime_validation: runtime_validation,
  persist_artifacts: true
)
host_validation = host_validation_bundle.fetch("host_validation")
playwright_validation = host_validation_bundle.fetch("playwright_validation")
export_download = Verification::ManualSupport.app_api_export_conversation!(
  conversation_id: conversation_id,
  session_token: app_api_session_token,
  destination_path: conversation_export_path
)
published_export_payload = read_zip_json(conversation_export_path, "conversation.json")
published_export_entry_names = zip_entry_names(conversation_export_path)

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
write_json(artifact_dir.join("evidence", "published-attachment-create.json"), published_attachment_create)
write_json(artifact_dir.join("evidence", "published-attachment-show.json"), published_attachment_show)
write_json(artifact_dir.join("evidence", "published-attachment-download.json"), published_attachment_download)

workflow_run = debug_payload.fetch("workflow_runs")
  .select { |candidate| candidate.fetch("turn_id") == turn_id }
  .max_by { |candidate| [candidate.fetch("created_at").to_s, candidate.fetch("workflow_run_id")] } || {}

Verification::CapstoneReviewArtifacts.install!(
  artifact_dir: artifact_dir,
  conversation_export_path: conversation_export_path,
  conversation_debug_export_path: conversation_debug_export_path,
  turn_feed: turn_feed,
  turn_runtime_events: turn_runtime_events,
  debug_payload: debug_payload,
  workflow_run_id: workflow_run.fetch("workflow_run_id")
)
workflow_mermaid_review_path = artifact_dir.join("review", "workflow-mermaid.md")
workflow_mermaid_review = workflow_mermaid_review_path.exist? ? workflow_mermaid_review_path.read : ""

observed_dag_shape = debug_payload.fetch("workflow_nodes")
  .select { |node| node.fetch("workflow_run_id") == workflow_run.fetch("workflow_run_id") }
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
selected_output_message = published_export_payload.fetch("messages")
  .reverse
  .find { |message| message.fetch("turn_public_id") == turn_id && message.fetch("role") == "agent" }
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
  Verification::ManualSupport.turn_live_activity_metrics(
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
alternating_roles = message_roles.each_slice(2).all? { |pair| pair == %w[user supervisor_agent] }
all_probes_accepted = supervision_probes.all? { |probe| probe.fetch("accepted_attempt").present? }
retry_round_count = supervision_probes.count { |probe| probe.fetch("accepted_attempt").to_i > 1 }
total_retry_attempts = supervision_probes.sum { |probe| probe.fetch("retry_attempts").length } - supervision_probes.length
minimum_live_probe_count = [1, [probe_questions.length, supervision_probes.length].min].max
minimum_metrics_changed_rounds = [live_activity_snapshots.length - 1, 0].max
minimum_progress_dimensions_advanced = live_activity_snapshots.length > 1 ? 2 : 1
minimum_progress_signal_count = [supervision_probes.length - 1, 1].min
minimum_distinct_supervisor_responses = [supervision_probes.length, 1].max
minimum_game_reference_count = [supervision_probes.length, 1].max
observed_conversation_state = {
  "conversation_state" => terminal.fetch("conversation").fetch("lifecycle_state"),
  "workflow_lifecycle_state" => workflow_run.fetch("lifecycle_state"),
  "workflow_wait_state" => workflow_run.fetch("wait_state"),
  "turn_lifecycle_state" => terminal.fetch("turn").fetch("lifecycle_state"),
  "selected_output_message_id" => output_message.public_id,
  "selected_output_content" => output_message.content,
}.compact
exported_attachment = Array(selected_output_message&.fetch("attachments", [])).find do |attachment|
  attachment.fetch("attachment_public_id") == published_attachment.fetch("attachment_id")
end
if exported_attachment.present?
  published_attachment_export_bytes = read_zip_entry(conversation_export_path, exported_attachment.fetch("relative_path"))
  published_attachment_export_sha256 = sha256_for_bytes(published_attachment_export_bytes)
end

write_json(
  artifact_dir.join("evidence", "published-attachment-inspection.json"),
  {
    "attachment_id" => published_attachment.fetch("attachment_id"),
    "upload_path" => published_attachment_upload_path.to_s,
    "upload_byte_size" => published_attachment_upload_byte_size,
    "upload_sha256" => published_attachment_upload_sha256,
    "download_path" => published_attachment_download.fetch("path"),
    "download_byte_size" => published_attachment_download.fetch("byte_size"),
    "download_sha256" => published_attachment_download_sha256,
    "export_relative_path" => exported_attachment&.fetch("relative_path"),
    "export_byte_size" => exported_attachment&.fetch("byte_size"),
    "export_sha256" => published_attachment_export_sha256,
    "entry_names" => published_attachment_entry_names,
  }
)

passed = dag_shape_passed &&
  expected_conversation_state.all? { |key, value| observed_conversation_state[key] == value } &&
  Verification::HostValidation.runtime_validation_passed?(runtime_validation) &&
  runtime_mentions_2048 &&
  Verification::HostValidation.host_validation_passed?(
    host_validation: host_validation,
    playwright_validation: playwright_validation
  ) &&
  conversation_export_path.exist? &&
  live_activity_snapshots.length >= minimum_live_probe_count &&
  live_activity_snapshots.none? do |snapshot|
    %w[completed failed canceled].include?(snapshot.fetch("turn").fetch("lifecycle_state"))
  end &&
  live_activity_snapshots.any? { |snapshot| snapshot.fetch("turn").fetch("lifecycle_state") == "active" } &&
  live_activity_snapshots.all? do |snapshot|
    Verification::ManualSupport.runtime_activity_present?(snapshot.fetch("runtime_events")) ||
      Verification::ManualSupport.feed_activity_present?(snapshot.fetch("feed"))
  end &&
  all_probes_accepted &&
  metrics_changed_rounds >= minimum_metrics_changed_rounds &&
  progress_dimensions_advanced.length >= minimum_progress_dimensions_advanced &&
  live_wording_present &&
  game_work_reference_count >= minimum_game_reference_count &&
  progress_signal_count >= minimum_progress_signal_count &&
  !refusal_or_apology_leak &&
  !completion_leak &&
  transcript_before_ids == transcript_after_ids &&
  supervision_messages.fetch("items").length >= (supervision_probes.length * 2) &&
  export_supervision_messages.length == supervision_messages.fetch("items").length &&
  alternating_roles &&
  export_supervision_messages.map { |message| message.fetch("role") } == message_roles &&
  supervisor_responses.uniq.length >= minimum_distinct_supervisor_responses &&
  published_attachment_create.fetch("method_id") == "publish_attachment" &&
  published_attachment.fetch("source_kind") == "runtime_generated" &&
  published_attachment_show.dig("attachment", "attachment_id") == published_attachment.fetch("attachment_id") &&
  published_attachment_show.dig("attachment", "publication_role") == "primary_deliverable" &&
  published_attachment_show.dig("attachment", "source_kind") == "runtime_generated" &&
  published_attachment_show.dig("attachment", "byte_size") == published_attachment_upload_byte_size &&
  published_attachment_download.fetch("byte_size") == published_attachment_upload_byte_size &&
  published_attachment_download_sha256 == published_attachment_upload_sha256 &&
  published_attachment_entry_names.include?("dist/index.html") &&
  published_attachment_entry_names.any? { |entry| entry.start_with?("dist/assets/") } &&
  exported_attachment.present? &&
  exported_attachment.fetch("publication_role") == "primary_deliverable" &&
  exported_attachment.fetch("source_kind") == "runtime_generated" &&
  exported_attachment.fetch("byte_size") == published_attachment_upload_byte_size &&
  exported_attachment.fetch("sha256") == published_attachment_upload_sha256 &&
  exported_attachment.fetch("sha256") == published_attachment_download_sha256 &&
  published_attachment_export_bytes.bytesize == exported_attachment.fetch("byte_size") &&
  published_attachment_export_sha256 == exported_attachment.fetch("sha256") &&
  published_export_entry_names.include?(exported_attachment.fetch("relative_path")) &&
  published_export_payload.fetch("delegation_summary") == [] &&
  workflow_mermaid_review_path.exist? &&
  workflow_mermaid_review.include?("Selected workflow run: `#{workflow_run.fetch("workflow_run_id")}`") &&
  workflow_mermaid_review.include?("```mermaid") &&
  workflow_mermaid_review.include?("flowchart LR") &&
  workflow_mermaid_review.include?(" --> ") &&
  workflow_mermaid_review.include?("state: ") &&
  workflow_mermaid_review.include?("policy: ")

write_text(
  artifact_dir.join("review", "summary.md"),
  <<~MD
    # 2048 Capstone Summary

    - passed: `#{passed}`
    - agent base url: `#{agent_base_url}`
    - runtime base url: `#{runtime_base_url}`
    - selector: `#{selector}`
    - dag shape passed: `#{dag_shape_passed}`
    - turn completed before all requested live probes: `#{turn_completed_before_all_live_probes}`
    - runtime validation passed: `#{Verification::HostValidation.runtime_validation_passed?(runtime_validation)}`
    - runtime browser mentioned 2048: `#{runtime_mentions_2048}`
    - host validation passed: `#{Verification::HostValidation.host_validation_passed?(host_validation: host_validation, playwright_validation: playwright_validation)}`
    - conversation export path: `#{conversation_export_path}`
    - conversation debug export path: `#{conversation_debug_export_path}`
    - generated app dir: `#{generated_app_dir}`
    - published attachment upload path: `#{published_attachment_upload_path}`
    - published attachment id: `#{published_attachment.fetch("attachment_id")}`
    - published attachment download path: `#{published_attachment_download.fetch("path")}`
    - published attachment export path: `#{exported_attachment&.fetch("relative_path")}`
    - published attachment upload sha256: `#{published_attachment_upload_sha256}`
    - published attachment download sha256: `#{published_attachment_download_sha256}`
    - published attachment export sha256: `#{published_attachment_export_sha256}`
    - review index: `#{artifact_dir.join("review", "index.md")}`
    - conversation transcript review: `#{artifact_dir.join("review", "conversation-transcript.md")}`
    - workflow mermaid review: `#{workflow_mermaid_review_path}`
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

result = Verification::ManualSupport.scenario_result(
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
    "workflow_mermaid_review_path" => workflow_mermaid_review_path.to_s,
    "selected_output_message_id" => output_message.public_id,
    "selected_output_content" => output_message.content,
    "published_attachment_create" => published_attachment_create,
    "published_attachment" => published_attachment_show.fetch("attachment"),
    "published_attachment_upload_path" => published_attachment_upload_path.to_s,
    "published_attachment_upload_byte_size" => published_attachment_upload_byte_size,
    "published_attachment_upload_sha256" => published_attachment_upload_sha256,
    "published_attachment_download" => published_attachment_download,
    "published_attachment_download_sha256" => published_attachment_download_sha256,
    "published_attachment_entry_names" => published_attachment_entry_names,
    "published_export_attachment" => exported_attachment,
    "published_attachment_export_sha256" => published_attachment_export_sha256,
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

Verification::ManualSupport.write_json(result)

unless result.fetch("passed")
  raise "2048 capstone verification failed; see #{artifact_dir}"
end
