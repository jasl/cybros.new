#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "pathname"
require "socket"
require "timeout"
require "zip"
require_relative "../manual_acceptance_support"

artifact_dir = Rails.root.join("..", "docs", "checklists", "artifacts", "2026-04-02-core-matrix-loop-fenix-2048-app-api-capstone").expand_path
workspace_root = Pathname.new(ENV.fetch("CAPSTONE_WORKSPACE_ROOT", Rails.root.join("..", "tmp", "fenix").to_s)).expand_path
generated_app_dir = workspace_root.join("game-2048")
runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
docker_container = ENV.fetch("FENIX_DOCKER_CONTAINER", "fenix-capstone")
fingerprint = ENV.fetch("CAPSTONE_RUNTIME_FINGERPRINT", "capstone-fenix-app-api-v1")
selector = ENV.fetch("CAPSTONE_SELECTOR", "candidate:openrouter/openai-gpt-5.4")
preview_port = Integer(ENV.fetch("CAPSTONE_HOST_PREVIEW_PORT", "4174"))
skip_worker_restart = ActiveModel::Type::Boolean.new.cast(ENV.fetch("SKIP_DOCKER_RUNTIME_WORKER_RESTART", "false"))

prompt = <<~PROMPT
Use `$using-superpowers`.

No screenshots or visual design review are needed.
You must still start the app and verify it in a browser session.
The design is approved.
Proceed autonomously now without asking more questions unless you are genuinely blocked.

Build a complete browser-playable React 2048 game in `/workspace/game-2048`.

Requirements:
- use modern React + Vite + TypeScript
- implement real 2048 rules: movement, merging, random tile spawning, score tracking, win/game-over behavior, and restart
- support both arrow keys and WASD
- add automated tests for the game logic
- run the tests and production build successfully
- start the app on `0.0.0.0:4173`
- verify it in a browser session
- use subagents when genuinely helpful
- end with a concise completion note
PROMPT

def write_json(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload))
end

def capture_command(*command, chdir:, env: {})
  stdout, stderr, status = Open3.capture3(env, *command, chdir: chdir.to_s)
  {
    "command" => command.join(" "),
    "cwd" => chdir.to_s,
    "success" => status.success?,
    "exit_status" => status.exitstatus,
    "stdout" => stdout,
    "stderr" => stderr,
  }
end

def wait_for_tcp_port!(host:, port:, timeout_seconds:)
  deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

  loop do
    begin
      socket = TCPSocket.new(host, port)
      socket.close
      return
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.2)
    end
  end
end

FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)
FileUtils.rm_rf(generated_app_dir)

ManualAcceptanceSupport.reset_backend_state!
bootstrap = ManualAcceptanceSupport.bootstrap_and_seed!
bundled = ManualAcceptanceSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  environment_fingerprint: "capstone-app-api-environment",
  fingerprint: fingerprint,
  sdk_version: "fenix-0.1.0"
)

machine_credential = bundled.fetch(:machine_credential)
deployment = bundled.fetch(:runtime).deployment

unless skip_worker_restart
  ManualAcceptanceSupport.restart_docker_fenix_runtime_worker!(
    machine_credential: machine_credential,
    container_name: docker_container
  )
end

conversation_context = ManualAcceptanceSupport.create_conversation!(deployment: deployment)
run = ManualAcceptanceSupport.execute_provider_turn_on_conversation!(
  conversation: conversation_context.fetch(:conversation),
  deployment: deployment,
  content: prompt,
  selector: selector
)

conversation = conversation_context.fetch(:conversation).reload
turn = run.fetch(:turn).reload
workflow_run = run.fetch(:workflow_run).reload

source_transcript = ManualAcceptanceSupport.app_api_conversation_transcript!(
  conversation_id: conversation.public_id,
  machine_credential: machine_credential,
  limit: 200
)
source_diagnostics_show = ManualAcceptanceSupport.app_api_conversation_diagnostics_show!(
  conversation_id: conversation.public_id,
  machine_credential: machine_credential
)
source_diagnostics_turns = ManualAcceptanceSupport.app_api_conversation_diagnostics_turns!(
  conversation_id: conversation.public_id,
  machine_credential: machine_credential
)

user_bundle_path = artifact_dir.join("conversation-export.zip")
debug_bundle_path = artifact_dir.join("conversation-debug-export.zip")

export_result = ManualAcceptanceSupport.app_api_export_conversation!(
  conversation_id: conversation.public_id,
  machine_credential: machine_credential,
  destination_path: user_bundle_path.to_s
)
debug_export_result = ManualAcceptanceSupport.app_api_debug_export_conversation!(
  conversation_id: conversation.public_id,
  machine_credential: machine_credential,
  destination_path: debug_bundle_path.to_s
)
import_result = ManualAcceptanceSupport.app_api_import_conversation_bundle!(
  workspace_id: conversation.workspace.public_id,
  zip_path: user_bundle_path.to_s,
  machine_credential: machine_credential
)
imported_conversation_id = import_result.dig("show", "import_request", "imported_conversation_id")

imported_transcript = ManualAcceptanceSupport.app_api_conversation_transcript!(
  conversation_id: imported_conversation_id,
  machine_credential: machine_credential,
  limit: 200
)
imported_diagnostics_show = ManualAcceptanceSupport.app_api_conversation_diagnostics_show!(
  conversation_id: imported_conversation_id,
  machine_credential: machine_credential
)

source_items = source_transcript.fetch("items").map { |item| item.slice("role", "slot", "variant_index", "content") }
imported_items = imported_transcript.fetch("items").map { |item| item.slice("role", "slot", "variant_index", "content") }
transcript_roundtrip_match = source_items == imported_items

debug_unpacked_dir = artifact_dir.join("debug-unpacked")
FileUtils.mkdir_p(debug_unpacked_dir)
parsed_debug = {}
Zip::File.open(debug_bundle_path.to_s) do |zip|
  zip.each do |entry|
    next if entry.directory?

    entry_path = Pathname(entry.name).cleanpath
    raise "unsafe debug bundle entry path: #{entry.name}" if entry_path.absolute? || entry_path.each_filename.include?("..")

    destination = debug_unpacked_dir.join(entry_path)
    FileUtils.mkdir_p(destination.dirname.to_s)
    contents = entry.get_input_stream.read
    File.binwrite(destination.to_s, contents)
    parsed_debug[entry.name] = JSON.parse(contents) if entry.name.end_with?(".json")
  end
end

usage_events = parsed_debug.fetch("usage_events.json")
command_runs = parsed_debug.fetch("command_runs.json")
process_runs = parsed_debug.fetch("process_runs.json")
tool_invocations = parsed_debug.fetch("tool_invocations.json")
subagent_sessions = parsed_debug.fetch("subagent_sessions.json")

provider_breakdown = usage_events.each_with_object(Hash.new { |hash, key| hash[key] = { "event_count" => 0, "input_tokens_total" => 0, "output_tokens_total" => 0 } }) do |entry, memo|
  key = [entry["provider_handle"], entry["model_ref"], entry["operation_kind"]]
  bucket = memo[key]
  bucket["provider_handle"] = entry["provider_handle"]
  bucket["model_ref"] = entry["model_ref"]
  bucket["operation_kind"] = entry["operation_kind"]
  bucket["event_count"] += 1
  bucket["input_tokens_total"] += entry["input_tokens"].to_i
  bucket["output_tokens_total"] += entry["output_tokens"].to_i
end.values.sort_by { |entry| [entry["provider_handle"], entry["model_ref"], entry["operation_kind"]] }

write_json(artifact_dir.join("source-transcript.json"), source_transcript)
write_json(artifact_dir.join("source-diagnostics-show.json"), source_diagnostics_show)
write_json(artifact_dir.join("source-diagnostics-turns.json"), source_diagnostics_turns)
write_json(artifact_dir.join("export-request-create.json"), export_result.fetch("create"))
write_json(artifact_dir.join("export-request-show.json"), export_result.fetch("show"))
write_json(artifact_dir.join("debug-export-request-create.json"), debug_export_result.fetch("create"))
write_json(artifact_dir.join("debug-export-request-show.json"), debug_export_result.fetch("show"))
write_json(artifact_dir.join("import-request-create.json"), import_result.fetch("create"))
write_json(artifact_dir.join("import-request-show.json"), import_result.fetch("show"))
write_json(artifact_dir.join("imported-transcript.json"), imported_transcript)
write_json(artifact_dir.join("imported-diagnostics-show.json"), imported_diagnostics_show)
write_json(artifact_dir.join("transcript-roundtrip-compare.json"), {
  "match" => transcript_roundtrip_match,
  "source_items" => source_items,
  "imported_items" => imported_items,
})

File.write(artifact_dir.join("export-roundtrip.md"), <<~MD)
# Export Roundtrip

Source conversation:
- `#{conversation.public_id}`

Imported conversation:
- `#{imported_conversation_id}`

Results:
- `ConversationExport` succeeded through `/app_api/conversation_export_requests`
- `ConversationDebugExport` succeeded through `/app_api/conversation_debug_export_requests`
- `ConversationImport` succeeded through `/app_api/conversation_bundle_import_requests`
- transcript roundtrip match: `#{transcript_roundtrip_match}`
- command runs exported: `#{command_runs.length}`
- process runs exported: `#{process_runs.length}`
- subagent sessions exported: `#{subagent_sessions.length}`
MD

host_validation_notes = []
if generated_app_dir.exist?
  if generated_app_dir.join("node_modules").exist?
    FileUtils.rm_rf(generated_app_dir.join("node_modules"))
    host_validation_notes << "Removed container-built node_modules before host validation."
  end
  FileUtils.rm_rf(generated_app_dir.join("dist"))
  FileUtils.rm_rf(generated_app_dir.join("coverage"))

  npm_install = capture_command("npm", "install", chdir: generated_app_dir)
  npm_test = capture_command("npm", "test", chdir: generated_app_dir)
  npm_build = capture_command("npm", "run", "build", chdir: generated_app_dir)

  preview_log = artifact_dir.join("host-preview.log")
  preview_pid = nil
  preview_http = nil
  begin
    preview_out = File.open(preview_log, "w")
    preview_pid = Process.spawn(
      { "BROWSER" => "none" },
      "npm", "run", "preview", "--", "--host", "127.0.0.1", "--port", preview_port.to_s,
      chdir: generated_app_dir.to_s,
      out: preview_out,
      err: preview_out
    )
    wait_for_tcp_port!(host: "127.0.0.1", port: preview_port, timeout_seconds: 20)
    preview_http = ManualAcceptanceSupport.http_get_json(
      "http://127.0.0.1:#{preview_port}",
      headers: { "Accept" => "text/html" }
    )
  rescue JSON::ParserError
    response, body = ManualAcceptanceSupport.http_get_response("http://127.0.0.1:#{preview_port}")
    raise "host preview failed: HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

    preview_http = {
      "status" => response.code.to_i,
      "contains_2048" => body.include?("2048"),
      "byte_size" => body.bytesize,
    }
  ensure
    if preview_pid.present?
      Process.kill("TERM", preview_pid) rescue nil
      Process.wait(preview_pid) rescue nil
    end
    preview_out&.close
  end

  write_json(artifact_dir.join("host-npm-install.json"), npm_install)
  write_json(artifact_dir.join("host-npm-test.json"), npm_test)
  write_json(artifact_dir.join("host-npm-build.json"), npm_build)
  write_json(artifact_dir.join("host-preview.json"), preview_http)

  File.write(artifact_dir.join("workspace-validation.md"), <<~MD)
  # Workspace Validation

  Workspace:
  - `#{generated_app_dir}`

  Operational notes:
  #{host_validation_notes.map { |note| "- #{note}" }.join("\n").presence || "- None."}

  Commands:
  - `npm install`
  - `npm test`
  - `npm run build`
  - `npm run preview -- --host 127.0.0.1 --port #{preview_port}`

  Results:
  - `npm install`: #{npm_install["success"] ? "passed" : "failed"}
  - `npm test`: #{npm_test["success"] ? "passed" : "failed"}
  - `npm run build`: #{npm_build["success"] ? "passed" : "failed"}
  - host preview reachable: #{preview_http["status"] == 200}
  - host preview contains `2048`: #{preview_http["contains_2048"] == true}
  MD
else
  File.write(artifact_dir.join("workspace-validation.md"), <<~MD)
  # Workspace Validation

  Expected generated app directory was missing:
  - `#{generated_app_dir}`
  MD
end

File.write(artifact_dir.join("playability-verification.md"), <<~MD)
# Playability Verification

Runtime-side verification:
- selected output message present: `#{turn.selected_output_message.present?}`
- agent reported browser verification in final output: `#{turn.selected_output_message&.content.to_s.include?("browser")}`

Debug evidence:
- browser tool calls observed: `#{tool_invocations.count { |entry| entry["tool_name"] == "browser_open" || entry["tool_name"] == "browser_get_content" }}`
- durable command runs exported: `#{command_runs.length}`
- durable process runs exported: `#{process_runs.length}`

Host-side validation:
- see `workspace-validation.md`
- host-side dependency reinstalls caused by platform-specific `node_modules` are treated as operational validation steps, not as agent-quality failures
MD

summary = {
  "conversation_id" => conversation.public_id,
  "workspace_id" => conversation.workspace.public_id,
  "turn_id" => turn.public_id,
  "workflow_run_id" => workflow_run.public_id,
  "deployment_id" => deployment.public_id,
  "execution_environment_id" => deployment.execution_environment.public_id,
  "selector" => selector,
  "workflow_state" => workflow_run.lifecycle_state,
  "turn_state" => turn.lifecycle_state,
  "user_bundle_path" => user_bundle_path.to_s,
  "debug_bundle_path" => debug_bundle_path.to_s,
  "imported_conversation_id" => imported_conversation_id,
  "transcript_roundtrip_match" => transcript_roundtrip_match,
  "provider_breakdown" => provider_breakdown,
  "usage_event_count" => usage_events.length,
  "input_tokens_total" => usage_events.sum { |entry| entry["input_tokens"].to_i },
  "output_tokens_total" => usage_events.sum { |entry| entry["output_tokens"].to_i },
  "command_run_count" => command_runs.length,
  "process_run_count" => process_runs.length,
  "tool_call_count" => tool_invocations.length,
  "subagent_session_count" => subagent_sessions.length,
}

write_json(artifact_dir.join("run-summary.json"), summary)
puts JSON.pretty_generate(summary)
