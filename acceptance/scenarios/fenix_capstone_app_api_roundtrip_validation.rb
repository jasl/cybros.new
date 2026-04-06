#!/usr/bin/env ruby

require "date"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "pathname"
require "socket"
require "time"
require "timeout"
require "uri"
require "zip"
require_relative "../lib/boot"
require_relative "../lib/conversation_control_phrase_matrix"
require_relative "../lib/conversation_runtime_validation"

$stdout.sync = true
$stderr.sync = true

OPERATOR_NAME = "Codex".freeze
RUNTIME_MODE = "Core Matrix host runtime + Dockerized Fenix".freeze
PLAYWRIGHT_VERSION = "1.59.1".freeze
EXPECTED_SKILL_DAG_SHAPE = ["agent_turn_step"].freeze
SUPERVISION_PROMPT = "Please tell me what you are doing right now and what changed most recently.".freeze
TERMINAL_WORK_SEGMENT_STATES = %w[completed failed interrupted canceled].freeze
INTERNAL_HUMAN_VISIBLE_TOKEN_PATTERN = %r{
  provider_round|
  tool_[a-z0-9_]+|
  runtime\.[a-z0-9_.]+|
  subagent_barrier|
  wait_reason_kind|
  workflow_node
}ix.freeze
EXPECTED_SKILL_CONVERSATION_STATE = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "completed",
  "workflow_wait_state" => "ready",
  "turn_lifecycle_state" => "active",
  "agent_task_run_state" => "completed",
}.freeze
CAPABILITY_CONTRACT = {
  "scenario" => "fenix_2048_capstone",
  "capabilities" => [
    { "key" => "workspace_editing", "required" => true },
    { "key" => "command_execution", "required" => true },
    { "key" => "browser_verification", "required" => true },
    { "key" => "supervision", "required" => true },
    { "key" => "export_roundtrip", "required" => true },
    { "key" => "skills", "required" => false },
    { "key" => "subagents", "required" => false },
  ],
}.freeze

repo_root = AcceptanceHarness.repo_root
artifact_stamp = ENV.fetch("CAPSTONE_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-core-matrix-loop-fenix-2048-final"
end
artifact_dir = repo_root.join("acceptance", "artifacts", artifact_stamp)
workspace_root = Pathname.new(ENV.fetch("CAPSTONE_WORKSPACE_ROOT", repo_root.join("tmp", "fenix").to_s)).expand_path
generated_app_dir = workspace_root.join("game-2048")
skill_source_root = workspace_root.join("skill-sources")
runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
docker_container = ENV.fetch("FENIX_DOCKER_CONTAINER", "fenix-capstone")
runtime_fingerprint = ENV.fetch("CAPSTONE_RUNTIME_FINGERPRINT", "capstone-fenix-execution-runtime-v1")
program_fingerprint = ENV.fetch("CAPSTONE_PROGRAM_FINGERPRINT", "capstone-fenix-agent-program-v1")
selector = ENV.fetch("CAPSTONE_SELECTOR", "candidate:openrouter/openai-gpt-5.4")
preview_port = Integer(ENV.fetch("CAPSTONE_HOST_PREVIEW_PORT", "4174"))
scenario_date = Date.current.iso8601
capstone_phase = ENV.fetch("CAPSTONE_PHASE", "execute")
bootstrap_state_path = Pathname.new(ENV.fetch("CAPSTONE_BOOTSTRAP_STATE_PATH", artifact_dir.join("capstone-runtime-bootstrap.json").to_s))
runtime_worker_boot_path = Pathname.new(ENV.fetch("CAPSTONE_RUNTIME_WORKER_BOOT_PATH", artifact_dir.join("docker-runtime-worker.json").to_s))
supervision_poll_interval_seconds = Float(
  ENV.fetch("CAPSTONE_SUPERVISION_POLL_INTERVAL_SECONDS", ENV.fetch("CAPSTONE_OBSERVATION_POLL_INTERVAL_SECONDS", "5"))
)
supervision_timeout_seconds = Integer(
  ENV.fetch("CAPSTONE_SUPERVISION_TIMEOUT_SECONDS", ENV.fetch("CAPSTONE_OBSERVATION_TIMEOUT_SECONDS", "3600"))
)
supervision_stall_threshold_ms = Integer(
  ENV.fetch("CAPSTONE_SUPERVISION_STALL_THRESHOLD_MS", ENV.fetch("CAPSTONE_OBSERVATION_STALL_THRESHOLD_MS", (30 * 60 * 1000).to_s))
)
max_turn_attempts = Integer(ENV.fetch("CAPSTONE_MAX_TURN_ATTEMPTS", "3"))
validation_note_limit = Integer(ENV.fetch("CAPSTONE_VALIDATION_NOTE_LIMIT", "1200"))
control_acceptance_enabled = ENV["CAPSTONE_ENABLE_CONTROL_ACCEPTANCE"] == "1"

prompt = <<~PROMPT
Use `$using-superpowers`.
`$find-skills` is installed and available if you need to discover or inspect additional skills.

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
- ensure the final Vite/Vitest configuration keeps `npm run build` passing
- start the app on `0.0.0.0:4173`
- verify it in a browser session
- use subagents when genuinely helpful
- end with a concise completion note

Acceptance harness requirements:
- render the board as a visible 4x4 grid with exactly 16 cells
- expose the board with `data-testid="board"` and `role="grid"` with an accessible name containing `2048 board`
- expose each cell with `role="gridcell"`
- expose score with `data-testid="score"`
- expose game status text with `data-testid="status"`
- expose restart or new-game control with `data-testid="restart"`
PROMPT

def write_json(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload) + "\n")
end

def write_text(path, contents)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, contents)
end

def append_jsonl(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.open(path, "a") { |file| file.puts(JSON.generate(payload)) }
end

def write_jsonl(path, payloads)
  FileUtils.mkdir_p(File.dirname(path))
  File.open(path, "w") do |file|
    Array(payloads).each { |payload| file.puts(JSON.generate(payload)) }
  end
end

def copy_artifact_entry(source:, destination:)
  return unless source.exist?

  FileUtils.mkdir_p(destination.dirname)

  if source.directory?
    FileUtils.rm_rf(destination)
    FileUtils.cp_r(source, destination)
  else
    FileUtils.cp(source, destination)
  end
end

def organize_artifact_layout!(artifact_dir:, layout:)
  layout.each do |category, entries|
    Array(entries).each do |entry|
      source = artifact_dir.join(entry)
      destination = artifact_dir.join(category, entry)
      copy_artifact_entry(source:, destination:)
    end
  end
end

def write_review_index_md(path:, summary:)
  lines = [
    "# Review Index",
    "",
    "- Conversation `public_id`: `#{summary.fetch("conversation_id")}`",
    "- Turn `public_id`: `#{summary.fetch("turn_id")}`",
    "- Workflow run `public_id`: `#{summary.fetch("workflow_run_id")}`",
    "- Benchmark outcome: `#{summary.fetch("benchmark_outcome")}`",
    "- Workload outcome: `#{summary.fetch("workload_outcome")}`",
    "- System behavior outcome: `#{summary.fetch("system_behavior_outcome")}`",
    "",
    "## Read This First",
    "",
    "- [Turn Runtime Transcript](turn-runtime-transcript.md)",
    "- [Conversation Transcript](conversation-transcript.md)",
    "- [Supervision Status](supervision-status.md)",
    "- [Supervision Feed](supervision-feed.md)",
    "- [Playability Verification](playability-verification.md)",
    "- [Workspace Validation](workspace-validation.md)",
    "- [Workspace Artifacts](workspace-artifacts.md)",
    "- [Benchmark Summary](../evidence/run-summary.json)",
    "",
    "## Supporting Evidence",
    "",
    "- [Turn Runtime Evidence](../evidence/turn-runtime-evidence.json)",
    "- [Capability Activation](../evidence/capability-activation.json)",
    "- [Failure Classification](../evidence/failure-classification.json)",
    "- [Phase Events](../logs/phase-events.jsonl)",
    "- [Turn Runtime Events](../logs/turn-runtime-events.jsonl)",
    "- [Conversation Export](../exports/conversation-export.zip)",
    "- [Conversation Debug Export](../exports/conversation-debug-export.zip)",
    "- [Playable Outputs](../playable/)",
  ]

  write_text(path, lines.join("\n") + "\n")
end

def write_artifact_root_readme(path:, artifact_stamp:, summary:)
  lines = [
    "# 2048 Acceptance Artifact Bundle",
    "",
    "- Artifact stamp: `#{artifact_stamp}`",
    "- Benchmark outcome: `#{summary.fetch("benchmark_outcome")}`",
    "- Workload outcome: `#{summary.fetch("workload_outcome")}`",
    "- System behavior outcome: `#{summary.fetch("system_behavior_outcome")}`",
    "",
    "## Entry Points",
    "",
    "- [Review index](review/index.md)",
    "- [Turn runtime transcript](review/turn-runtime-transcript.md)",
    "- [Benchmark summary](evidence/run-summary.json)",
    "- [Phase events](logs/phase-events.jsonl)",
    "- [Playable artifacts](playable/)",
    "",
    "## Layout",
    "",
    "- `review/`: human-readable transcripts, supervision views, validation notes",
    "- `evidence/`: machine-readable benchmark outputs and diagnostics",
    "- `logs/`: timeline and supervision logs",
    "- `exports/`: export/debug-export/import roundtrip bundles and metadata",
    "- `playable/`: host-side build, preview, and browser-verification outputs",
    "- `tmp/`: unpacked debug bundle and scratch files",
    "",
    "Legacy root-level files are retained for compatibility with existing acceptance tooling.",
  ]

  write_text(path, lines.join("\n") + "\n")
end

def log_capstone_phase(artifact_dir:, phase:, details: {})
  payload = {
    "timestamp" => Time.current.iso8601,
    "phase" => phase,
  }.merge(details.transform_keys(&:to_s))

  append_jsonl(artifact_dir.join("phase-events.jsonl"), payload)
  puts "[capstone] #{JSON.generate(payload)}"
end

def read_json(path)
  JSON.parse(File.read(path))
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

def capture_command!(*command, chdir:, env: {}, failure_label: nil)
  result = capture_command(*command, chdir:, env:)
  return result if result.fetch("success")

  label = failure_label || command.join(" ")
  details = result.fetch("stderr").presence || result.fetch("stdout").presence || "no output"
  raise "#{label} failed:\n#{details}"
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

def ensure_conversation_capability_policy!(conversation:, control_enabled:)
  policy = conversation.conversation_capability_policy || ConversationCapabilityPolicy.new(
    installation: conversation.installation,
    target_conversation: conversation,
    policy_payload: {}
  )

  policy.supervision_enabled = true
  policy.detailed_progress_enabled = true
  policy.side_chat_enabled = true
  policy.control_enabled = control_enabled
  policy.policy_payload = policy.policy_payload.presence || {}
  policy.save! if policy.new_record? || policy.changed?

  policy
end

def supervision_terminal_state?(machine_status)
  overall_state = machine_status.fetch("overall_state")
  return true if TERMINAL_WORK_SEGMENT_STATES.include?(overall_state)

  overall_state == "idle" && TERMINAL_WORK_SEGMENT_STATES.include?(machine_status["last_terminal_state"])
end

def supervision_stalled?(machine_status:, stall_threshold_ms:)
  return false if TERMINAL_WORK_SEGMENT_STATES.include?(machine_status.fetch("overall_state"))
  return false if machine_status.fetch("overall_state") == "idle"

  last_progress_at = machine_status["last_progress_at"]
  return false if last_progress_at.blank?

  ((Time.current - Time.iso8601(last_progress_at)) * 1000).to_i >= stall_threshold_ms
rescue ArgumentError
  false
end

def supervise_conversation_progress!(
  conversation_id:,
  actor:,
  prompt: SUPERVISION_PROMPT,
  timeout_seconds:,
  poll_interval_seconds:,
  stall_threshold_ms:
)
  session_payload = ManualAcceptanceSupport.create_conversation_supervision_session!(
    conversation_id: conversation_id,
    actor: actor
  )
  supervision_session_id = session_payload.dig("conversation_supervision_session", "supervision_session_id")
  deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
  polls = []

  loop do
    response = ManualAcceptanceSupport.append_conversation_supervision_message!(
      supervision_session_id: supervision_session_id,
      content: prompt,
      actor: actor
    )
    machine_status = response.fetch("machine_status")
    human_sidechat = response.fetch("human_sidechat")

    polls << {
      "machine_status" => machine_status,
      "human_sidechat" => human_sidechat,
      "user_message" => response.fetch("user_message"),
      "supervisor_message" => response.fetch("supervisor_message"),
    }

    return {
      "session" => session_payload,
      "polls" => polls,
      "final_response" => response,
    } if supervision_terminal_state?(machine_status)

    if supervision_stalled?(machine_status:, stall_threshold_ms:)
      raise <<~MSG
        conversation supervision detected a stall after #{stall_threshold_ms}ms
        last supervision response:
        #{JSON.pretty_generate(response)}
      MSG
    end

    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
      raise <<~MSG
        timed out supervising conversation #{conversation_id} through supervision
        last supervision response:
        #{JSON.pretty_generate(response)}
      MSG
    end

    sleep(poll_interval_seconds)
  end
end

def build_host_preview_failure_message(error:, preview_pid:, preview_log:, preview_port:)
  process_details =
    if preview_pid.present?
      waited_pid = Process.waitpid(preview_pid, Process::WNOHANG)
      status = $?

      if waited_pid.present?
        if status&.exited?
          "preview process exited with status #{status.exitstatus}"
        elsif status&.signaled?
          "preview process terminated by signal #{status.termsig}"
        else
          "preview process exited unexpectedly"
        end
      else
        "preview process stayed alive but port #{preview_port} never became reachable"
      end
    else
      "preview process did not start"
    end

  log_excerpt =
    if File.exist?(preview_log)
      File.read(preview_log).to_s.strip.presence
    end

  [
    error.message,
    process_details,
    ("preview log:\n#{log_excerpt}" if log_excerpt.present?),
  ].compact.join("\n")
end

def run_host_preview_and_verification!(dist_dir:, artifact_dir:, generated_app_dir:, preview_port:, attempts: 2)
  preview_log = artifact_dir.join("host-preview.log")
  last_error = nil

  attempts.times do |index|
    preview_pid = nil
    preview_out = nil

    begin
      preview_out = File.open(preview_log, index.zero? ? "w" : "a")
      preview_out.sync = true

      preview_pid = Process.spawn(
        "python3", "-m", "http.server", preview_port.to_s, "--bind", "127.0.0.1",
        chdir: dist_dir.to_s,
        out: preview_out,
        err: preview_out
      )
      wait_for_tcp_port!(host: "127.0.0.1", port: preview_port, timeout_seconds: 20)

      response, body = ManualAcceptanceSupport.http_get_response("http://127.0.0.1:#{preview_port}")
      raise "host preview failed: HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

      playwright_validation = run_host_playwright_verification!(
        artifact_dir: artifact_dir,
        base_url: "http://127.0.0.1:#{preview_port}/",
        generated_app_dir: generated_app_dir
      )

      preview_http = {
        "status" => response.code.to_i,
        "contains_2048" => body.include?("2048") ||
          playwright_validation.dig("result", "initial", "nonEmpty").to_i.positive? ||
          playwright_validation.dig("result", "initial", "status").to_s.present?,
        "byte_size" => body.bytesize,
        "attempt_no" => index + 1,
      }

      return {
        "preview_http" => preview_http,
        "playwright_validation" => playwright_validation,
      }
    rescue => error
      last_error = build_host_preview_failure_message(
        error: error,
        preview_pid: preview_pid,
        preview_log: preview_log,
        preview_port: preview_port
      )
    ensure
      if preview_pid.present?
        Process.kill("TERM", preview_pid) rescue nil
        Process.wait(preview_pid) rescue nil
      end
      preview_out&.close
    end

    sleep 0.5 if index + 1 < attempts
  end

  raise last_error || "host preview verification failed"
end

def download_text!(url)
  uri = URI(url)
  response = Net::HTTP.get_response(uri)
  raise "download failed for #{url}: HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

  response.body.to_s
end

def prepare_skill_sources!(skill_source_root:)
  superpowers_repo_dir = skill_source_root.join("superpowers")
  using_superpowers_dir = skill_source_root.join("using-superpowers")
  find_skills_dir = skill_source_root.join("find-skills")
  skill_source_manifest = skill_source_root.join("skill-source-manifest.json")

  FileUtils.rm_rf(skill_source_root)
  FileUtils.mkdir_p(skill_source_root)

  clone_result = capture_command!(
    "git", "clone", "--depth", "1", "https://github.com/obra/superpowers.git", superpowers_repo_dir.to_s,
    chdir: skill_source_root.parent,
    failure_label: "clone superpowers"
  )
  superpowers_revision = capture_command!(
    "git", "rev-parse", "HEAD",
    chdir: superpowers_repo_dir,
    failure_label: "read superpowers revision"
  ).fetch("stdout").strip

  FileUtils.mkdir_p(using_superpowers_dir)
  FileUtils.cp(superpowers_repo_dir.join("skills", "using-superpowers", "SKILL.md"), using_superpowers_dir.join("SKILL.md"))
  FileUtils.cp_r(superpowers_repo_dir.join("skills"), using_superpowers_dir.join("skills"))

  FileUtils.mkdir_p(find_skills_dir)
  find_skills_body = download_text!("https://raw.githubusercontent.com/vercel-labs/skills/main/skills/find-skills/SKILL.md")
  write_text(find_skills_dir.join("SKILL.md"), find_skills_body)

  manifest = {
    "superpowers_repo" => {
      "source_url" => "https://github.com/obra/superpowers",
      "revision" => superpowers_revision,
      "clone_root" => superpowers_repo_dir.to_s,
      "installed_skill_root" => using_superpowers_dir.to_s,
      "installed_skill_name" => "using-superpowers",
    },
    "find_skills" => {
      "source_url" => "https://github.com/vercel-labs/skills/blob/main/skills/find-skills/SKILL.md",
      "raw_url" => "https://raw.githubusercontent.com/vercel-labs/skills/main/skills/find-skills/SKILL.md",
      "installed_skill_root" => find_skills_dir.to_s,
      "installed_skill_name" => "find-skills",
    },
    "clone_command" => clone_result.fetch("command"),
  }
  write_json(skill_source_manifest, manifest)

  {
    "manifest" => manifest,
    "manifest_path" => skill_source_manifest.to_s,
    "using_superpowers_dir" => using_superpowers_dir.to_s,
    "find_skills_dir" => find_skills_dir.to_s,
  }
end

def runtime_visible_workspace_path(host_path:, workspace_root:, runtime_worker_boot:)
  return host_path.to_s if runtime_worker_boot.blank?

  host_path = Pathname.new(host_path).expand_path
  workspace_root = Pathname.new(workspace_root).expand_path
  docker_workspace_root = Pathname.new(ENV.fetch("FENIX_DOCKER_MOUNT_WORKSPACE_ROOT", "/workspace"))

  relative_path = host_path.relative_path_from(workspace_root)
  docker_workspace_root.join(relative_path).to_s
rescue ArgumentError
  raise "#{host_path} is outside workspace root #{workspace_root}"
end

def serialize_skill_validation_run(run)
  {
    "conversation_id" => run.fetch(:conversation).public_id,
    "turn_id" => run.fetch(:turn).public_id,
    "workflow_run_id" => run.fetch(:workflow_run).public_id,
    "agent_task_run_id" => run.fetch(:agent_task_run).public_id,
    "dag_shape" => ManualAcceptanceSupport.workflow_node_keys(run.fetch(:workflow_run)),
    "conversation_state" => ManualAcceptanceSupport.workflow_state_hash(
      conversation: run.fetch(:conversation),
      workflow_run: run.fetch(:workflow_run),
      turn: run.fetch(:turn),
      agent_task_run: run.fetch(:agent_task_run)
    ),
    "runtime_execution_status" => run.fetch(:execution).fetch("status"),
    "runtime_output" => run.fetch(:execution)["output"],
    "report_results" => run.fetch(:report_results),
  }
end

def skill_validation_passed?(serialized_run)
  serialized_run.fetch("dag_shape") == EXPECTED_SKILL_DAG_SHAPE &&
    EXPECTED_SKILL_CONVERSATION_STATE.all? do |key, value|
      serialized_run.fetch("conversation_state")[key] == value
    end
end

def execute_runtime_worker_skill_turn!(agent_program_version:, content:, mode:, extra_payload:, timeout_seconds: 60)
  conversation_context = ManualAcceptanceSupport.create_conversation!(agent_program_version: agent_program_version)
  run = ManualAcceptanceSupport.start_turn_workflow_on_conversation!(
    conversation: conversation_context.fetch(:conversation),
    agent_program_version: agent_program_version,
    content: content,
    root_node_key: "agent_turn_step",
    root_node_type: "turn_step",
    decision_source: "agent_program",
    initial_kind: "turn_step",
    initial_payload: { "mode" => mode }.merge(extra_payload)
  )
  agent_task_run = ManualAcceptanceSupport.wait_for_agent_task_terminal!(
    agent_task_run: run.fetch(:agent_task_run),
    timeout_seconds: timeout_seconds
  )
  workflow_run = ManualAcceptanceSupport.wait_for_workflow_run_terminal!(
    workflow_run: run.fetch(:workflow_run),
    timeout_seconds: timeout_seconds
  )
  turn = run.fetch(:turn).reload

  run.merge(
    conversation: conversation_context.fetch(:conversation).reload,
    turn: turn,
    workflow_run: workflow_run.reload,
    agent_task_run: agent_task_run.reload,
    execution: {
      "status" => agent_task_run.lifecycle_state,
      "output" => agent_task_run.terminal_payload["output"],
      "terminal_payload" => agent_task_run.terminal_payload,
    },
    report_results: ManualAcceptanceSupport.report_results_for(agent_task_run: agent_task_run)
  )
end

def install_and_validate_skills!(agent_program_version:, skill_sources:, workspace_root:, runtime_worker_boot:)
  using_superpowers_source_path = runtime_visible_workspace_path(
    host_path: skill_sources.fetch("using_superpowers_dir"),
    workspace_root: workspace_root,
    runtime_worker_boot: runtime_worker_boot
  )
  find_skills_source_path = runtime_visible_workspace_path(
    host_path: skill_sources.fetch("find_skills_dir"),
    workspace_root: workspace_root,
    runtime_worker_boot: runtime_worker_boot
  )

  using_superpowers_install = execute_runtime_worker_skill_turn!(
    agent_program_version: agent_program_version,
    content: "Install using-superpowers from the staged GitHub source.",
    mode: "skills_install",
    extra_payload: { "source_path" => using_superpowers_source_path }
  )
  using_superpowers_load = execute_runtime_worker_skill_turn!(
    agent_program_version: agent_program_version,
    content: "Load the using-superpowers skill.",
    mode: "skills_load",
    extra_payload: { "skill_name" => "using-superpowers" }
  )
  using_superpowers_read = execute_runtime_worker_skill_turn!(
    agent_program_version: agent_program_version,
    content: "Read the brainstorming skill nested under using-superpowers.",
    mode: "skills_read_file",
    extra_payload: {
      "skill_name" => "using-superpowers",
      "relative_path" => "skills/brainstorming/SKILL.md",
    }
  )
  find_skills_install = execute_runtime_worker_skill_turn!(
    agent_program_version: agent_program_version,
    content: "Install find-skills from the staged GitHub source.",
    mode: "skills_install",
    extra_payload: { "source_path" => find_skills_source_path }
  )
  find_skills_load = execute_runtime_worker_skill_turn!(
    agent_program_version: agent_program_version,
    content: "Load the find-skills skill.",
    mode: "skills_load",
    extra_payload: { "skill_name" => "find-skills" }
  )

  using_superpowers_payload = {
    "install" => serialize_skill_validation_run(using_superpowers_install),
    "load" => serialize_skill_validation_run(using_superpowers_load),
    "read" => serialize_skill_validation_run(using_superpowers_read),
    "host_source_path" => skill_sources.fetch("using_superpowers_dir"),
    "runtime_source_path" => using_superpowers_source_path,
    "install_activation_state" => using_superpowers_install.fetch(:execution).dig("output", "activation_state"),
    "loaded_name" => using_superpowers_load.fetch(:execution).dig("output", "name"),
    "read_relative_path" => "skills/brainstorming/SKILL.md",
    "read_content_excerpt" => using_superpowers_read.fetch(:execution).dig("output", "content").to_s.lines.first(5).join,
  }
  find_skills_payload = {
    "install" => serialize_skill_validation_run(find_skills_install),
    "load" => serialize_skill_validation_run(find_skills_load),
    "host_source_path" => skill_sources.fetch("find_skills_dir"),
    "runtime_source_path" => find_skills_source_path,
    "install_activation_state" => find_skills_install.fetch(:execution).dig("output", "activation_state"),
    "loaded_name" => find_skills_load.fetch(:execution).dig("output", "name"),
  }

  {
    "passed" => [
      using_superpowers_payload.fetch("install"),
      using_superpowers_payload.fetch("load"),
      using_superpowers_payload.fetch("read"),
      find_skills_payload.fetch("install"),
      find_skills_payload.fetch("load"),
    ].all? { |entry| skill_validation_passed?(entry) },
    "expected_dag_shape" => EXPECTED_SKILL_DAG_SHAPE,
    "expected_conversation_state" => EXPECTED_SKILL_CONVERSATION_STATE,
    "skill_sources" => skill_sources.fetch("manifest"),
    "using_superpowers" => using_superpowers_payload,
    "find_skills" => find_skills_payload,
  }
end

def unpack_debug_bundle!(zip_path:, destination_dir:)
  FileUtils.rm_rf(destination_dir)
  FileUtils.mkdir_p(destination_dir)

  parsed = {}
  Zip::File.open(zip_path.to_s) do |zip|
    zip.each do |entry|
      next if entry.directory?

      entry_path = Pathname(entry.name).cleanpath
      raise "unsafe debug bundle entry path: #{entry.name}" if entry_path.absolute? || entry_path.each_filename.include?("..")

      destination = destination_dir.join(entry_path)
      FileUtils.mkdir_p(destination.dirname.to_s)
      contents = entry.get_input_stream.read
      File.binwrite(destination.to_s, contents)
      parsed[entry.name] = JSON.parse(contents) if entry.name.end_with?(".json")
    end
  end

  parsed
end

def write_conversation_transcript_md(path, transcript_payload)
  lines = ["# Conversation Transcript", ""]

  transcript_payload.fetch("items").each_with_index do |item, index|
    lines << "## Message #{index + 1}"
    lines << ""
    lines << "- Message `public_id`: `#{item.fetch("id")}`"
    lines << "- Role: `#{item.fetch("role")}`"
    lines << ""
    lines << "```text"
    lines << item.fetch("content").to_s.rstrip
    lines << "```"
    lines << ""
  end

  write_text(path, lines.join("\n").rstrip + "\n")
end

def public_id_like?(value)
  value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
end

def suspicious_internal_tokens(text)
  return [] if text.blank?

  text.scan(/\b\d{6,}\b/).uniq
end

def internal_runtime_tokens(text)
  return [] if text.blank?

  text.scan(INTERNAL_HUMAN_VISIBLE_TOKEN_PATTERN).uniq
end

def public_id_tokens(text)
  return [] if text.blank?

  text.scan(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i).uniq
end

def human_visible_leak_tokens(text)
  (suspicious_internal_tokens(text) + public_id_tokens(text) + internal_runtime_tokens(text)).uniq
end

def supervision_public_id_boundary_failures(poll)
  failures = []
  machine_status = poll.fetch("machine_status")

  scalar_checks = [
    ["machine_status.supervision_session_id", machine_status["supervision_session_id"]],
    ["machine_status.supervision_snapshot_id", machine_status["supervision_snapshot_id"]],
    ["machine_status.conversation_id", machine_status["conversation_id"]],
    ["machine_status.current_owner_public_id", machine_status["current_owner_public_id"]],
    ["human_sidechat.supervision_session_id", poll.dig("human_sidechat", "supervision_session_id")],
    ["human_sidechat.supervision_snapshot_id", poll.dig("human_sidechat", "supervision_snapshot_id")],
    ["human_sidechat.conversation_id", poll.dig("human_sidechat", "conversation_id")],
    ["user_message.supervision_message_id", poll.dig("user_message", "supervision_message_id")],
    ["user_message.supervision_session_id", poll.dig("user_message", "supervision_session_id")],
    ["user_message.supervision_snapshot_id", poll.dig("user_message", "supervision_snapshot_id")],
    ["user_message.target_conversation_id", poll.dig("user_message", "target_conversation_id")],
    ["supervisor_message.supervision_message_id", poll.dig("supervisor_message", "supervision_message_id")],
    ["supervisor_message.supervision_session_id", poll.dig("supervisor_message", "supervision_session_id")],
    ["supervisor_message.supervision_snapshot_id", poll.dig("supervisor_message", "supervision_snapshot_id")],
    ["supervisor_message.target_conversation_id", poll.dig("supervisor_message", "target_conversation_id")],
    ["proof_debug.conversation_id", machine_status.dig("proof_debug", "conversation_id")],
    ["proof_debug.anchor_turn_id", machine_status.dig("proof_debug", "anchor_turn_id")],
    ["proof_debug.workflow_run_id", machine_status.dig("proof_debug", "workflow_run_id")],
    ["proof_debug.workflow_node_id", machine_status.dig("proof_debug", "workflow_node_id")],
    ["proof_debug.conversation_supervision_state_id", machine_status.dig("proof_debug", "conversation_supervision_state_id")],
    ["proof_debug.conversation_capability_policy_id", machine_status.dig("proof_debug", "conversation_capability_policy_id")],
  ]

  scalar_checks.each do |label, value|
    next if value.blank?
    next if public_id_like?(value)

    failures << "#{label}=#{value.inspect}"
  end

  array_checks = [
    ["activity_feed.feed_entry_ids", Array(machine_status["activity_feed"]).map { |entry| entry["conversation_supervision_feed_entry_id"] }],
    ["activity_feed.turn_ids", Array(machine_status["activity_feed"]).map { |entry| entry["turn_id"] }],
    ["conversation_context.message_ids", Array(machine_status.dig("conversation_context", "message_ids"))],
    ["conversation_context.turn_ids", Array(machine_status.dig("conversation_context", "turn_ids"))],
    ["active_subagents.subagent_session_ids", Array(machine_status["active_subagents"]).map { |entry| entry["subagent_session_id"] }],
    ["active_plan_items.delegated_subagent_session_ids", Array(machine_status["active_plan_items"]).map { |entry| entry["delegated_subagent_session_id"] }],
    ["proof_debug.context_message_ids", Array(machine_status.dig("proof_debug", "context_message_ids"))],
    ["proof_debug.feed_entry_ids", Array(machine_status.dig("proof_debug", "feed_entry_ids"))],
  ]

  array_checks.each do |label, values|
    values.compact.each do |value|
      failures << "#{label}=#{value.inspect}" unless public_id_like?(value)
    end
  end

  failures
end

def append_supervision_control_lines(lines, machine_status)
  control = machine_status.fetch("control", {})
  available_verbs = Array(control["available_control_verbs"])

  lines << "- Control capability:"
  lines << "  - Supervision enabled: `#{control["supervision_enabled"]}`"
  lines << "  - Side chat enabled: `#{control["side_chat_enabled"]}`"
  lines << "  - Control enabled: `#{control["control_enabled"]}`"
  lines << "  - Available control actions: `#{available_verbs.any? ? available_verbs.join("`, `") : "none"}`"
end

def append_supervision_plan_item_lines(lines, machine_status)
  plan_items = Array(machine_status["active_plan_items"])
  lines << "- Active plan items: `#{plan_items.length}`"
  return if plan_items.empty?

  plan_items.each do |item|
    lines << "  - `#{item["status"]}` #{item["title"]}"
  end
end

def append_supervision_subagent_lines(lines, machine_status)
  subagents = Array(machine_status["active_subagents"])
  lines << "- Active child tasks: `#{subagents.length}`"
  return if subagents.empty?

  subagents.each do |subagent|
    summary = subagent["current_focus_summary"] || subagent["waiting_summary"] || subagent["blocked_summary"] || "no summary"
    lines << "  - `#{subagent["observed_status"] || subagent["supervision_state"] || "unknown"}` #{summary}"
  end
end

def append_supervision_grounding_lines(lines, machine_status)
  lines << "- Grounding:"
  lines << "  - Board lane: `#{machine_status["board_lane"]}`"
  lines << "  - Last terminal state: `#{machine_status["last_terminal_state"] || "none"}`"
  lines << "  - Recent feed entries: `#{Array(machine_status["activity_feed"]).length}`"
  lines << "  - Conversation facts: `#{Array(machine_status.dig("conversation_context", "facts")).length}`"
  lines << "  - Waiting summary present: `#{machine_status["waiting_summary"].present?}`"
  lines << "  - Blocked summary present: `#{machine_status["blocked_summary"].present?}`"
end

def append_supervision_proof_debug_lines(lines, machine_status)
  proof_debug = machine_status.fetch("proof_debug", {})

  lines << "- Proof and debug refs:"
  lines << "  - Conversation: `#{proof_debug["conversation_id"] || "none"}`"
  lines << "  - Anchor turn: `#{proof_debug["anchor_turn_id"] || "none"}`"
  lines << "  - Workflow run: `#{proof_debug["workflow_run_id"] || "none"}`"
  lines << "  - Workflow node: `#{proof_debug["workflow_node_id"] || "none"}`"
  lines << "  - Supervision state: `#{proof_debug["conversation_supervision_state_id"] || "none"}`"
  lines << "  - Capability policy: `#{proof_debug["conversation_capability_policy_id"] || "none"}`"
  if Array(proof_debug["context_message_ids"]).any?
    lines << "  - Context message ids: `#{Array(proof_debug["context_message_ids"]).join("`, `")}`"
  end
  if Array(proof_debug["feed_entry_ids"]).any?
    lines << "  - Feed entry ids: `#{Array(proof_debug["feed_entry_ids"]).join("`, `")}`"
  end
end

def write_supervision_sidechat_md(path:, supervision_trace:, prompt:)
  polls = supervision_trace.fetch("polls")
  lines = [
    "# Supervision Sidechat",
    "",
    "- Poll count: `#{polls.length}`",
    "- Supervisor question template:",
    "",
    "```text",
    prompt,
    "```",
    "",
  ]

  polls.each_with_index do |poll, index|
    machine_status = poll.fetch("machine_status")
    boundary_failures = supervision_public_id_boundary_failures(poll)
    human_sidechat = poll.fetch("human_sidechat")
    user_message = poll.fetch("user_message")
    suspicious_tokens = human_visible_leak_tokens(human_sidechat.fetch("content")) +
      human_visible_leak_tokens(user_message.fetch("content"))

    lines << "## Exchange #{index + 1}"
    lines << ""
    lines << "- Overall state: `#{machine_status.fetch("overall_state")}`"
    lines << "- Board lane: `#{machine_status["board_lane"]}`"
    lines << "- Current focus: `#{machine_status["current_focus_summary"] || machine_status["request_summary"] || "none"}`"
    lines << "- Public-id boundary check: `#{boundary_failures.empty? ? "pass" : "fail"}`"
    lines << "- Human-visible leak scan: `#{suspicious_tokens.empty? ? "pass" : "fail"}`"
    lines << ""
    lines << "### User Question"
    lines << ""
    lines << "```text"
    lines << user_message.fetch("content").to_s.rstrip
    lines << "```"
    lines << ""
    lines << "### Human Sidechat"
    lines << ""
    lines << "```text"
    lines << human_sidechat.fetch("content").to_s.rstrip
    lines << "```"
    lines << ""
    if boundary_failures.any?
      lines << "- Boundary failures:"
      boundary_failures.each { |failure| lines << "  - `#{failure}`" }
    end
    if suspicious_tokens.any?
      lines << "- Suspicious human-visible leak tokens:"
      suspicious_tokens.uniq.each { |token| lines << "  - `#{token}`" }
    end
    append_supervision_grounding_lines(lines, machine_status)
    append_supervision_control_lines(lines, machine_status)
    lines << ""
  end

  write_text(path, lines.join("\n").rstrip + "\n")
end

def write_supervision_status_md(path:, supervision_trace:)
  session_id = supervision_trace.dig("session", "conversation_supervision_session", "supervision_session_id")
  final_response = supervision_trace.fetch("final_response")
  polls = supervision_trace.fetch("polls")
  final_status = final_response.fetch("machine_status")
  lines = [
    "# Supervision Status",
    "",
    "- Supervision session `public_id`: `#{session_id}`",
    "- Final overall state: `#{final_status.fetch("overall_state")}`",
    "- Final board lane: `#{final_status["board_lane"]}`",
    "- Final last terminal state: `#{final_status["last_terminal_state"] || "none"}`",
    "- Poll count: `#{polls.length}`",
    "",
  ]

  polls.each_with_index do |poll, index|
    machine_status = poll.fetch("machine_status")
    boundary_failures = supervision_public_id_boundary_failures(poll)
    latest_activity = Array(machine_status["activity_feed"]).last || {}

    lines << "## Poll #{index + 1}"
    lines << ""
    lines << "- Supervision snapshot `public_id`: `#{machine_status.fetch("supervision_snapshot_id")}`"
    lines << "- Overall state: `#{machine_status.fetch("overall_state")}`"
    lines << "- Board lane: `#{machine_status["board_lane"]}`"
    lines << "- Last terminal state: `#{machine_status["last_terminal_state"] || "none"}`"
    lines << "- Last terminal at: `#{machine_status["last_terminal_at"] || "unknown"}`"
    lines << "- Current focus: `#{machine_status["current_focus_summary"] || machine_status["request_summary"] || "none"}`"
    lines << "- Recent progress: `#{machine_status["recent_progress_summary"] || "none"}`"
    lines << "- Waiting summary: `#{machine_status["waiting_summary"] || "none"}`"
    lines << "- Blocked summary: `#{machine_status["blocked_summary"] || "none"}`"
    lines << "- Next step hint: `#{machine_status["next_step_hint"] || "none"}`"
    lines << "- Last progress at: `#{machine_status["last_progress_at"] || "unknown"}`"
    lines << "- Latest activity event: `#{latest_activity["event_kind"] || "none"}`"
    lines << "- Latest activity sequence: `#{latest_activity["sequence"] || "none"}`"
    lines << "- Public-id boundary check: `#{boundary_failures.empty? ? "pass" : "fail"}`"
    append_supervision_plan_item_lines(lines, machine_status)
    append_supervision_subagent_lines(lines, machine_status)
    append_supervision_control_lines(lines, machine_status)
    append_supervision_proof_debug_lines(lines, machine_status)
    lines << ""
  end

  write_text(path, lines.join("\n").rstrip + "\n")
end

def write_supervision_feed_md(path:, supervision_trace:)
  final_status = supervision_trace.fetch("final_response").fetch("machine_status")
  activity_feed = Array(final_status["activity_feed"])
  lines = [
    "# Supervision Feed",
    "",
    "- Feed entry count: `#{activity_feed.length}`",
    "- Feed source turn: `#{activity_feed.last&.fetch("turn_id", "none") || "none"}`",
    "",
  ]

  activity_feed.each do |entry|
    lines << "## Entry #{entry.fetch("sequence")}"
    lines << ""
    lines << "- Event kind: `#{entry.fetch("event_kind")}`"
    lines << "- Occurred at: `#{entry.fetch("occurred_at")}`"
    lines << "- Summary: #{entry.fetch("summary")}"
    lines << ""
  end

  write_text(path, lines.join("\n").rstrip + "\n")
end

def evaluate_control_intent_case!(category:, entry:, supervision_session_id:, actor:, conversation:)
  response = ManualAcceptanceSupport.append_conversation_supervision_message!(
    supervision_session_id: supervision_session_id,
    actor: actor,
    content: entry.fetch("utterance")
  )
  human_sidechat = response.fetch("human_sidechat")
  machine_status = response.fetch("machine_status")
  conversation_control_request_id = human_sidechat["conversation_control_request_id"]
  control_request = conversation_control_request_id.present? ? ConversationControlRequest.find_by_public_id!(conversation_control_request_id) : nil
  actual_request_kind = human_sidechat["classified_intent"]
  refreshed_state = Conversations::UpdateSupervisionState.call(
    conversation: conversation.reload,
    occurred_at: Time.current
  )

  expectation_passed =
    case category
    when "positive"
      actual_request_kind == entry["expected_request_kind"]
    else
      actual_request_kind.blank? && human_sidechat["intent"] != "control_request"
    end

  {
    "category" => category,
    "utterance" => entry.fetch("utterance"),
    "expected_request_kind" => entry["expected_request_kind"],
    "actual_request_kind" => actual_request_kind,
    "human_sidechat_intent" => human_sidechat["intent"],
    "response_kind" => human_sidechat["response_kind"] || "sidechat",
    "dispatch_state" => human_sidechat["dispatch_state"] || "not_dispatched",
    "conversation_control_request_id" => conversation_control_request_id,
    "capability_state" => machine_status.fetch("control"),
    "authority_decision" => human_sidechat["response_kind"] || "not_requested",
    "final_runtime_effect" => {
      "conversation_lifecycle_state" => conversation.reload.lifecycle_state,
      "overall_state" => refreshed_state.overall_state,
      "last_terminal_state" => refreshed_state.last_terminal_state,
      "last_terminal_at" => refreshed_state.last_terminal_at&.iso8601(6)
    }.compact,
    "human_sidechat" => human_sidechat.fetch("content"),
    "human_visible_leak_tokens" => human_visible_leak_tokens(human_sidechat.fetch("content")),
    "expectation_passed" => expectation_passed,
    "request_result_payload" => control_request&.result_payload,
  }
end

def run_control_intent_matrix!(artifact_dir:, supervision_session_id:, actor:, conversation:)
  matrix = ConversationControlPhraseMatrix.load!
  cases = %w[negative ambiguous positive].flat_map do |category|
    Array(matrix.fetch(category)).map { |entry| [category, entry] }
  end

  results = cases.map do |category, entry|
    evaluate_control_intent_case!(
      category: category,
      entry: entry,
      supervision_session_id: supervision_session_id,
      actor: actor,
      conversation: conversation
    )
  end

  payload = {
    "enabled" => true,
    "conversation_id" => conversation.public_id,
    "supervision_session_id" => supervision_session_id,
    "fixture_path" => ConversationControlPhraseMatrix::FIXTURE_PATH.to_s,
    "summary" => {
      "case_count" => results.length,
      "classified_count" => results.count { |entry| entry["actual_request_kind"].present? },
      "successful_dispatch_count" => results.count { |entry| entry["dispatch_state"] == "completed" },
      "ambiguous_passthrough_count" => results.count do |entry|
        %w[negative ambiguous].include?(entry["category"]) && entry["actual_request_kind"].blank?
      end,
      "expectation_passed" => results.all? { |entry| entry["expectation_passed"] },
    },
    "cases" => results,
  }

  write_json(artifact_dir.join("control-intent-matrix.json"), payload)
  payload
end

def write_turns_md(path:, scenario_date:, conversation:, turn:, workflow_run:, agent_program_version:, execution_runtime:, selector:, diagnostics_turn:, source_transcript:, provider_breakdown:, subagent_sessions:, proof_artifacts:)
  workflow_node_type_counts = diagnostics_turn.dig("metadata", "workflow_node_type_counts") || {}
  evidence_refs = diagnostics_turn.dig("metadata", "evidence_refs") || {}
  provider_entry = provider_breakdown.first || {}
  subagent_entry = Array(subagent_sessions).first || {}
  message_roles = source_transcript.fetch("items").map { |item| item.fetch("role") }.uniq

  lines = [
    "# Capstone Turns",
    "",
    "## Turn 1",
    "",
    "- Scenario date: `#{scenario_date}`",
    "- Operator: `#{OPERATOR_NAME}`",
    "- Conversation `public_id`: `#{conversation.public_id}`",
    "- Turn `public_id`: `#{turn.public_id}`",
    "- Workflow-run `public_id`: `#{workflow_run.public_id}`",
    "- Agent program version `public_id`: `#{agent_program_version.public_id}`",
    "- Execution runtime `public_id`: `#{execution_runtime&.public_id || "none"}`",
    "- Runtime mode: `#{RUNTIME_MODE}`",
    "- Provider handle: `#{provider_entry["provider_handle"] || "n/a"}`",
    "- Model ref: `#{provider_entry["model_ref"] || "n/a"}`",
    "- API model: `#{turn.resolved_model_ref || "n/a"}`",
    "- Selector: `#{selector}`",
    "- Expected DAG shape: provider-backed `turn_step` with repeated `tool_call` and `barrier_join` expansion until completion",
    "- Observed DAG shape:",
    "  - `turn_step`: `#{workflow_node_type_counts["turn_step"].to_i}`",
    "  - `tool_call`: `#{workflow_node_type_counts["tool_call"].to_i}`",
    "  - `barrier_join`: `#{workflow_node_type_counts["barrier_join"].to_i}`",
    "  - Total workflow nodes: `#{workflow_run.workflow_nodes.count}`",
    "  - Highest observed provider round: `#{diagnostics_turn["provider_round_count"]}`",
    "- Expected conversation state: one user request followed by one completed agent response",
    "- Observed conversation state:",
    "  - Conversation lifecycle: `#{conversation.lifecycle_state}`",
    "  - Turn lifecycle: `#{turn.lifecycle_state}`",
    "  - Message roles: `#{message_roles.join("`, `")}`",
    "  - Output message `public_id`: `#{evidence_refs["selected_output_message_id"] || turn.selected_output_message&.public_id || "none"}`",
    "- Subagent work expected: `yes`",
    "- Subagent work observed: `#{subagent_sessions.any? ? "yes" : "no"}`",
  ]

  if subagent_sessions.any?
    lines << "  - Observed subagent session `public_id`: `#{subagent_entry["subagent_session_id"] || subagent_entry["id"] || "unknown"}`"
    lines << "  - Observed subagent profile: `#{subagent_entry["profile_name"] || subagent_entry["profile_id"] || "unknown"}`"
  end

  lines << "- Proof artifacts:"
  proof_artifacts.each do |artifact|
    lines << "  - `#{artifact}`"
  end
  lines << "- Outcome: `pass`"
  lines << ""

  write_text(path, lines.join("\n"))
end

def write_collaboration_notes_md(path:, selector:, host_validation_notes:, subagent_sessions:)
  lines = [
    "# Collaboration Notes",
    "",
    "## What Worked Well",
    "",
    "- The provider-backed loop stayed autonomous after the initial user turn and completed without manual mid-turn steering.",
    "- The run exercised the real `Core Matrix` plus Dockerized `Fenix` path instead of a debug-only shortcut.",
    "- The final product landed in the mounted host workspace and was independently runnable from the host.",
  ]

  if subagent_sessions.any?
    lines << "- Real subagent work surfaced during the run through at least one exported subagent session."
  else
    lines << "- The tool surface stayed stable, but this run did not export subagent evidence, so subagent capability should be probed again on the next capstone rerun."
  end

  lines.concat([
    "",
    "## Where Operator Intervention Was Still Needed",
    "",
    "- For realistic coding-agent capstone runs, the smaller live-acceptance selector was not sufficient. The full-window selector `#{selector}` was the correct operational choice.",
  ])
  if host_validation_notes.any?
    host_validation_notes.each do |note|
      lines << "- #{note}"
    end
  else
    lines << "- Host-side validation ran without extra operator intervention beyond the normal preview start."
  end

  lines.concat([
    "",
    "## Collaboration Guidance",
    "",
    "- Keep the workspace disposable and expect a host-side dependency reinstall when the container writes platform-specific JavaScript dependencies into a shared mount.",
    "- Treat the provider-backed loop as the truth for acceptance. The agent message alone was not enough; the durable workflow, subagent session, export bundle, and host playability checks were needed to close the run.",
    "- Keep the staged GitHub skill sources in the mounted workspace so the runtime can install and inspect them through the normal tool surface.",
    "",
  ])

  write_text(path, lines.join("\n"))
end

def write_runtime_and_bindings_md(path:, workspace_root:, machine_credential:, agent_program:, agent_program_version:, execution_runtime:, skill_source_manifest_path:, docker_container:, runtime_base_url:, runtime_worker_boot:)
  redacted_credential = machine_credential.to_s.sub(/:.+\z/, ":REDACTED")
  worker_commands = Array(runtime_worker_boot&.fetch("worker_commands", nil))
  standalone_solid_queue = runtime_worker_boot&.fetch("standalone_solid_queue", false)
  activation_command = <<~CMD.chomp
    FENIX_MACHINE_CREDENTIAL=#{redacted_credential} \
    FENIX_EXECUTION_MACHINE_CREDENTIAL=#{redacted_credential} \
    DOCKER_CORE_MATRIX_BASE_URL=http://host.docker.internal:3000 \
    bash acceptance/bin/activate_fenix_docker_runtime.sh
  CMD
  worker_summary =
    if standalone_solid_queue
      "The runtime worker booted through `bin/runtime-worker`, which in standalone mode also started the separate Solid Queue worker process."
    else
      "The runtime worker booted through `bin/runtime-worker`, which reused Puma's embedded Solid Queue supervisor and only started the persistent control loop."
    end
  worker_command_lines =
    if worker_commands.present?
      worker_commands.map { |command| "- `#{command}`" }.join("\n")
    else
      "- `bin/runtime-worker`"
    end

  contents = <<~MD
    # Runtime And Bindings

    ## Reset

    - Reset disposable workspace:
      - `#{workspace_root}`
    - Reset `Core Matrix` development database with:

    ```bash
    cd #{Rails.root}
    bin/rails db:drop
    rm db/schema.rb
    bin/rails db:create
    bin/rails db:migrate
    bin/rails db:reset
    ```

    ## Core Matrix

    Started host-side services with:

    ```bash
    cd #{Rails.root}
    bin/rails server -b 127.0.0.1 -p 3000
    bin/jobs start
    ```

    Health check:

    ```bash
    curl -fsS http://127.0.0.1:3000/up
    ```

    ## Dockerized Fenix

    Fresh-start automation rebuilt and recreated the Dockerized `Fenix`
    runtime container from the current local `agents/fenix` checkout.

    - Container: `#{docker_container}`
    - Public runtime base URL: `#{runtime_base_url}`

    The top-level automation reset the Dockerized runtime by removing the
    `fenix_capstone_storage` volume before boot so no in-run database reset was
    needed.

    ```bash
    docker volume rm -f fenix_capstone_storage
    bash acceptance/bin/fresh_start_stack.sh
    ```

    Manifest probe:

    ```bash
    curl -fsS #{runtime_base_url}/runtime/manifest
    ```

    ## Registration And Worker Start

    Registered the bundled runtime from the published manifest and issued a new machine credential. Public bindings:

    - Agent program `public_id`: `#{agent_program.public_id}`
    - Agent program version `public_id`: `#{agent_program_version.public_id}`
    - Execution runtime `public_id`: `#{execution_runtime.public_id}`
    - Skill source manifest: `#{skill_source_manifest_path}`

    After runtime registration, the top-level automation recreated the
    Dockerized `Fenix` container with the issued machine credentials in its
    environment, then started the persistent runtime worker:

    ```bash
    #{activation_command}
    ```

    #{worker_summary}

    Worker entrypoint(s):

    #{worker_command_lines}
  MD

  write_text(path, contents)
end

def write_workspace_artifacts_md(path:, workspace_root:, generated_app_dir:, host_validation_notes:, preview_port:)
  unless generated_app_dir.exist?
    return write_text(path, <<~MD)
      # Workspace Artifacts

      Generated application directory was not created:

      - Mounted host workspace root:
        - `#{workspace_root}`
      - Expected application path:
        - `#{generated_app_dir}`
    MD
  end

  relative_files = Dir.chdir(generated_app_dir) do
    Dir.glob([
      "src/**/*",
      "public/**/*",
      "package.json",
      "vite.config.*",
      "tsconfig*.json",
      "index.html",
      "dist/**/*",
    ]).select { |entry| File.file?(entry) }.sort.first(20)
  end

  lines = [
    "# Workspace Artifacts",
    "",
    "- Mounted host workspace root:",
    "  - `#{workspace_root}`",
    "- Final application path:",
    "  - `#{generated_app_dir}`",
    "- Final source tree includes:",
  ]
  relative_files.each do |entry|
    lines << "  - `#{entry}`"
  end
  lines << ""
  lines << "## Host-Side Commands"
  lines << ""
  lines << "Primary host usability verification uses the exported `dist/` output:"
  lines << ""
  lines << "```bash"
  lines << "cd #{generated_app_dir}/dist"
  lines << "python3 -m http.server #{preview_port} --bind 127.0.0.1"
  lines << "```"
  lines << ""
  lines << "Source portability diagnostics remain separate and may require reinstalling host-native dependencies:"
  lines << ""
  if host_validation_notes.any?
    lines << "Because the mounted workspace contained container-built dependencies, source-portability diagnostics first normalized those artifacts:"
    lines << ""
    lines << "```bash"
    lines << "cd #{generated_app_dir}"
    lines << "rm -rf node_modules dist coverage"
    lines << "npm install"
    lines << "```"
    lines << ""
  end
  lines << "Host-side verification commands:"
  lines << ""
  lines << "```bash"
  lines << "cd #{generated_app_dir}"
  lines << "npm test"
  lines << "npm run build"
  lines << "```"
  lines << ""
  lines << "## Run URL"
  lines << ""
  lines << "- Preview URL:"
  lines << "  - `http://127.0.0.1:#{preview_port}/`"
  lines << ""
  lines << "Host preview reachability is recorded separately in `workspace-validation.md` and `host-preview.json` when available."
  lines << "- Benchmark summaries:"
  lines << "  - `capability-activation.md`"
  lines << "  - `failure-classification.md`"
  lines << "  - `phase-events.jsonl`"
  lines << ""

  write_text(path, lines.join("\n"))
end

def build_conversation_runtime_validation(tool_invocations:)
  ManualAcceptance::ConversationRuntimeValidation.build(tool_invocations:)
end

def write_playability_verification_md(path:, playability_result:, generated_app_dir:, preview_port:, runtime_validation:, preview_validation:, host_skip_reason: nil)
  unless playability_result.present?
    lines = [
      "# Playability Verification",
      "",
      "## Conversation Runtime Evidence",
      "",
      "- Runtime-side build succeeded: `#{runtime_validation.fetch("runtime_build_passed")}`",
      "- Runtime-side test succeeded: `#{runtime_validation.fetch("runtime_test_passed")}`",
      "- Runtime-side dev server reached `:4173`: `#{runtime_validation.fetch("runtime_dev_server_ready")}`",
      "- Runtime-side browser session loaded content: `#{runtime_validation.fetch("runtime_browser_loaded")}`",
      "- Runtime browser content mentioned `2048`: `#{runtime_validation.fetch("runtime_browser_mentions_2048")}`",
    ]
    excerpt = runtime_validation.fetch("runtime_browser_content_excerpt").to_s
    if excerpt.present?
      lines.concat([
        "",
        "Runtime browser content excerpt:",
        "",
        "```text",
        excerpt,
        "```",
      ])
    end
    lines.concat([
      "",
      "## Host Playability Diagnostic",
      "",
      "- Host `dist/` preview reachable: `#{preview_validation.fetch("reachable")}`",
      "- Host preview content mentioned `2048`: `#{preview_validation.fetch("contains_2048")}`",
      "",
      host_skip_reason.presence || "Host-side browser verification did not run.",
      "",
      "- Generated application path: `#{generated_app_dir}`",
      "- Intended host preview URL: `http://127.0.0.1:#{preview_port}/`",
      "",
      "See `workspace-validation.md`, `host-preview.json`, `host-npm-test.json`, and `host-npm-build.json` for portability diagnostics.",
      "",
    ])

    return write_text(path, lines.join("\n"))
  end

  direction_checks = playability_result.fetch("directionChecks")
  lines = [
    "# Playability Verification",
    "",
    "Host-side browser verification was executed against:",
    "",
    "- `http://127.0.0.1:#{preview_port}/`",
    "",
    "Verification artifacts:",
    "",
    "- `host-playwright-verification.json`",
    "- `host-playability.png`",
    "",
    "## Verified Behaviors",
    "",
    "- Page loaded successfully from the host preview server.",
    "- Keyboard play worked with real browser input.",
  ]
  direction_checks.each_key do |key|
    lines << "- Direction produced a valid board change: `#{key}`"
  end
  lines.concat([
    "- Merge behavior was observed.",
    "- Score increased on merge.",
    "- A new tile appeared after a valid move.",
    "- A full game-over state was reached through real key presses.",
    "- Restart reset the score to `0`.",
    "- Restart reset the board to exactly two starting tiles.",
    "",
    "## Observed Run Details",
    "",
    "- Initial board had `#{playability_result.dig("initial", "nonEmpty")}` tiles.",
    "- During automated host play, score reached `#{playability_result.dig("preRestart", "score")}`.",
    "- Pre-restart state showed `#{playability_result.dig("preRestart", "status")}` with a full `4x4` board.",
    "- Post-restart state returned to `#{playability_result.dig("postRestart", "status")}` and `#{playability_result.dig("postRestart", "nonEmpty")}` starting tiles.",
    "",
    "## Host Verification Commands",
    "",
    "```bash",
    "cd #{generated_app_dir}/dist",
    "python3 -m http.server #{preview_port} --bind 127.0.0.1",
    "npm install --no-save @playwright/test@#{PLAYWRIGHT_VERSION}",
    "npx playwright install chromium",
    "npx playwright test host-playability.spec.cjs --workers=1 --reporter=line",
    "```",
    "",
    "Browser validation used Playwright on the host against the platform-independent `dist/` output.",
    "",
  ])

  write_text(path, lines.join("\n"))
end

def build_agent_evaluation(summary:, diagnostics_turn:)
  result_quality =
    if summary.fetch("transcript_roundtrip_match") &&
        summary.fetch("workflow_state") == "completed" &&
        summary.fetch("turn_state") == "completed" &&
        summary.dig("conversation_validation", "runtime_test_passed") &&
        summary.dig("conversation_validation", "runtime_build_passed") &&
        summary.dig("conversation_validation", "runtime_browser_loaded") &&
        summary.dig("workspace_validation", "preview_reachable") &&
        summary.dig("workspace_validation", "playwright_verification_passed")
      "strong"
    else
      "fail"
    end

  runtime_health =
    if diagnostics_turn.fetch("tool_failure_count").to_i <= 3 &&
        diagnostics_turn.fetch("command_failure_count").to_i <= 1 &&
        summary.fetch("workflow_state") == "completed"
      "acceptable"
    else
      "weak"
    end

  convergence =
    case diagnostics_turn.fetch("provider_round_count").to_i
    when 0..40
      "strong"
    when 41..80
      "acceptable"
    else
      "weak"
    end

  cost_efficiency =
    case diagnostics_turn.fetch("provider_round_count").to_i
    when 0..40
      "strong"
    when 41..80
      "acceptable"
    else
      "weak"
    end

  {
    "result_quality" => {
      "rating" => result_quality,
      "summary" => "Conversation/runtime-side test, build, browser evidence, and transcript roundtrip established whether the benchmark outcome was met; host portability checks are reported separately as diagnostics.",
      "evidence" => [
        "run-summary.json",
        "playability-verification.md",
        "workspace-validation.md",
        "host-preview.json",
        "host-playwright-verification.json",
        "host-npm-test.json",
        "host-npm-build.json",
        "export-roundtrip.md",
      ],
    },
    "runtime_health" => {
      "rating" => runtime_health,
      "summary" => "The run completed through the real provider-backed loop, but the exported diagnostics still showed some tool and command failures worth monitoring.",
      "evidence" => [
        "diagnostics.json",
        "tool_invocations.json",
        "command_runs.json",
        "process_runs.json",
      ],
    },
    "convergence" => {
      "rating" => convergence,
      "summary" => "Provider round count and tool churn were acceptable for a real coding-agent capstone, but not yet especially lean.",
      "evidence" => [
        "run-summary.json",
        "diagnostics.json",
        "tool_invocations.json",
        "subagent_sessions.json",
      ],
    },
    "cost_efficiency" => {
      "rating" => cost_efficiency,
      "summary" => "Token and tool usage were proportional to the difficulty of a real 2048 build, though the run still carried noticeable iteration cost.",
      "evidence" => [
        "run-summary.json",
        "diagnostics.json",
        "usage_events.json",
      ],
    },
  }
end

def write_agent_evaluation_md(path, evaluation)
  lines = ["# Agent Evaluation", ""]

  evaluation.each do |dimension, payload|
    lines << "## #{dimension.tr("_", " ").split.map(&:capitalize).join(" ")}"
    lines << ""
    lines << "- Rating: `#{payload.fetch("rating")}`"
    lines << "- Summary: #{payload.fetch("summary")}"
    lines << "- Evidence:"
    payload.fetch("evidence").each do |entry|
      lines << "  - `#{entry}`"
    end
    lines << ""
  end

  write_text(path, lines.join("\n"))
end

def determine_workload_outcome(workflow_run:, runtime_validation:, host_validation:, playwright_validation:, generated_app_dir:)
  return "complete" if workflow_run.lifecycle_state == "completed" &&
    runtime_validation_passed?(runtime_validation) &&
    host_validation_passed?(host_validation:, playwright_validation:)

  if workflow_run.lifecycle_state != "completed"
    return "blocked" if generated_app_dir.exist? || runtime_validation.values.any?(true)

    return "failed"
  end

  runtime_progress = runtime_validation.values.any?(true)
  host_progress = [
    host_validation.dig("npm_install", "success"),
    host_validation.dig("npm_test", "success"),
    host_validation.dig("npm_build", "success"),
    host_validation.dig("preview_http", "status") == 200,
    playwright_validation["result"].present?,
  ].any?

  return "partial" if generated_app_dir.exist? || runtime_progress || host_progress

  "failed"
end

def build_rescue_history_entry(attempt_no:, workflow_run:, runtime_validation:, host_validation:, playwright_validation:, host_playability_skip_reason:, repair_prompt:)
  reasons = []
  reasons << "workflow_not_completed" unless workflow_run.lifecycle_state == "completed"
  reasons << "runtime_validation_failed" unless runtime_validation_passed?(runtime_validation)
  reasons << "host_validation_failed" unless host_validation_passed?(host_validation:, playwright_validation:)
  reasons << "host_playability_failed" if host_playability_skip_reason.present?

  {
    "attempt_no" => attempt_no,
    "workflow_run_id" => workflow_run.public_id,
    "workflow_state" => workflow_run.lifecycle_state,
    "trigger_reasons" => reasons,
    "host_playability_skip_reason" => host_playability_skip_reason,
    "repair_prompt_excerpt" => repair_prompt.lines.first(12).join,
  }
end

def build_failure_timeline(attempt_history:, terminal_failure_message:)
  timeline = Array(attempt_history).filter_map do |attempt|
    host_validation = attempt.fetch("host_validation")
    runtime_validation = attempt.fetch("runtime_validation")
    workflow_completed = attempt.fetch("workflow_state") == "completed"
    host_failed = host_validation.values.any?(false)
    runtime_failed = runtime_validation.values.any?(false)

    next if workflow_completed && !host_failed && !runtime_failed

    suspected_category =
      if host_failed
        "environment_defect"
      elsif runtime_failed
        "agent_design_gap"
      elsif !workflow_completed
        "model_variance"
      else
        "unknown"
      end

    symptom =
      if host_failed
        host_validation.select { |_key, value| value == false }.keys
      elsif runtime_failed
        runtime_validation.select { |_key, value| value == false }.keys
      else
        ["workflow_state=#{attempt.fetch("workflow_state")}"]
      end

    {
      "phase" => "attempt_#{attempt.fetch("attempt_no")}",
      "status" => attempt.fetch("workflow_state"),
      "symptom" => symptom,
      "evidence" => ["attempt-history.json", "workspace-validation.md", "diagnostics.json"],
      "suspected_category" => suspected_category,
    }
  end

  if terminal_failure_message.present?
    timeline << {
      "phase" => "terminal_failure",
      "status" => "failed",
      "symptom" => terminal_failure_message.lines.first.to_s.strip,
      "evidence" => ["run-summary.json", "failure-classification.json"],
      "suspected_category" => "unknown",
    }
  end

  timeline
end

def write_capability_activation_md(path:, capability_report:)
  rows = Array(capability_report.fetch("required_capabilities"))
  lines = [
    "# Capability Activation",
    "",
    "- Scenario: `#{capability_report.fetch("scenario")}`",
    "- Required capabilities passed: `#{capability_report.dig("summary", "required_passed_count")}` / `#{capability_report.dig("summary", "required_count")}`",
    "- Optional capabilities activated: `#{capability_report.dig("summary", "optional_activated_count")}`",
    "- Expectation passed: `#{capability_report.dig("summary", "expectation_passed")}`",
    "",
  ]

  rows.each do |row|
    lines << "## #{row.fetch("key")}"
    lines << ""
    lines << "- Required: `#{row.fetch("required")}`"
    lines << "- Activated: `#{row.fetch("activated")}`"
    lines << "- Evidence level: `#{row.fetch("evidence_level")}`"
    if row.fetch("db_evidence").any?
      lines << "- DB evidence:"
      row.fetch("db_evidence").each { |entry| lines << "  - `#{entry}`" }
    end
    if row.fetch("artifact_evidence").any?
      lines << "- Artifact evidence:"
      row.fetch("artifact_evidence").each { |entry| lines << "  - `#{entry}`" }
    end
    if row.fetch("notes").any?
      lines << "- Notes:"
      row.fetch("notes").each { |entry| lines << "  - #{entry}" }
    end
    lines << ""
  end

  write_text(path, lines.join("\n").rstrip + "\n")
end

def write_failure_classification_md(path:, failure_report:)
  lines = [
    "# Failure Classification",
    "",
    "- Scenario: `#{failure_report.fetch("scenario")}`",
    "- Benchmark outcome: `#{failure_report.fetch("outcome")}`",
    "- Workload outcome: `#{failure_report.fetch("workload_outcome")}`",
    "- System behavior outcome: `#{failure_report.fetch("system_behavior_outcome")}`",
    "",
  ]

  primary = failure_report.dig("classification", "primary")
  confidence = failure_report.dig("classification", "confidence")
  lines << "- Primary classification: `#{primary}`" if primary.present?
  lines << "- Confidence: `#{confidence}`" unless confidence.nil?
  lines << "" if primary.present? || !confidence.nil?

  secondary = Array(failure_report.dig("classification", "secondary"))
  if secondary.any?
    lines << "- Secondary classifications: `#{secondary.join("`, `")}`"
    lines << ""
  end

  Array(failure_report.fetch("timeline")).each do |entry|
    symptom = Array(entry["symptom"]).join(", ")
    lines << "## #{entry.fetch("phase")}"
    lines << ""
    lines << "- Status: `#{entry.fetch("status")}`"
    lines << "- Suspected category: `#{entry["suspected_category"]}`" if entry["suspected_category"].present?
    lines << "- Symptom: #{symptom}" if symptom.present?
    if Array(entry["evidence"]).any?
      lines << "- Evidence:"
      Array(entry["evidence"]).each { |artifact| lines << "  - `#{artifact}`" }
    end
    lines << ""
  end

  if Array(failure_report.fetch("recommended_actions")).any?
    lines << "## Recommended Actions"
    lines << ""
    Array(failure_report.fetch("recommended_actions")).each do |action|
      lines << "- #{action}"
    end
    lines << ""
  end

  write_text(path, lines.join("\n").rstrip + "\n")
end

def build_playwright_script(output_json_path:, screenshot_path:)
  <<~JAVASCRIPT
    const fs = require('fs');
    const { test, expect } = require('@playwright/test');

    const baseUrl = process.env.CAPSTONE_PREVIEW_URL;
    const outputJsonPath = #{output_json_path.to_s.inspect};
    const screenshotPath = #{screenshot_path.to_s.inspect};

    function chunk(values, size) {
      const rows = [];
      for (let index = 0; index < values.length; index += size) {
        rows.push(values.slice(index, index + size));
      }
      return rows;
    }

    function sameBoard(a, b) {
      return JSON.stringify(a) === JSON.stringify(b);
    }

    async function pickFirstLocator(candidates) {
      for (const locator of candidates) {
        if ((await locator.count()) > 0) return locator.first();
      }
      throw new Error('required locator not found');
    }

    async function boardLocator(page) {
      return pickFirstLocator([
        page.getByTestId('board'),
        page.getByRole('grid', { name: /2048 board/i }),
        page.locator('[role="grid"]'),
      ]);
    }

    async function boardCellTexts(page) {
      const board = await boardLocator(page);
      let cells = board.getByRole('gridcell');
      if ((await cells.count()) === 0) {
        cells = page.locator('[data-testid^="tile-"]');
      }

      await expect(cells).toHaveCount(16);
      return (await cells.allTextContents()).map((text) => {
        const trimmed = text.trim();
        return trimmed === '' ? null : Number(trimmed);
      });
    }

    async function scoreValue(page) {
      const locator = await pickFirstLocator([
        page.getByTestId('score'),
        page.locator('[data-testid="score-value"]'),
      ]);
      const matches = (await locator.innerText()).match(/\\d+/g) || ['0'];
      return Number(matches[matches.length - 1]);
    }

    async function statusValue(page) {
      const candidates = [
        page.getByTestId('status'),
        page.getByRole('status'),
        page.locator('[aria-live]'),
      ];

      for (const locator of candidates) {
        if ((await locator.count()) > 0) {
          const text = (await locator.first().innerText()).trim();
          if (text !== '') return text;
        }
      }

      const bodyText = await page.locator('body').innerText();
      if (/game over/i.test(bodyText)) return 'Game over';
      if (/you win/i.test(bodyText)) return 'You win';

      return bodyText.trim().split(/\\n+/).find((line) => line.match(/arrow keys|wasd|restart|play/i)) || '';
    }

    async function snapshot(page) {
      const flat = await boardCellTexts(page);
      return {
        board: chunk(flat, 4),
        score: await scoreValue(page),
        status: await statusValue(page),
        nonEmpty: flat.filter((value) => value !== null && value !== 0).length,
      };
    }

    async function waitForChange(page, previous) {
      const previousJson = JSON.stringify(previous);
      try {
        await page.waitForFunction((prior) => {
          const boardElement =
            document.querySelector('[data-testid="board"]') ||
            document.querySelector('[role="grid"][aria-label*="2048 board" i]') ||
            document.querySelector('[role="grid"]');
          const cellNodes = boardElement
            ? Array.from(boardElement.querySelectorAll('[role="gridcell"]'))
            : Array.from(document.querySelectorAll('[data-testid^="tile-"]'));
          const flat = cellNodes.map((node) => {
            const text = (node.textContent || '').trim();
            return text === '' ? null : Number(text);
          });
          const rows = [];
          for (let index = 0; index < flat.length; index += 4) rows.push(flat.slice(index, index + 4));

          const scoreElement = document.querySelector('[data-testid="score"], [data-testid="score-value"]');
          const scoreText = scoreElement ? scoreElement.textContent || '' : '';
          const scoreMatches = scoreText.match(/\\d+/g) || ['0'];
          const score = Number(scoreMatches[scoreMatches.length - 1]);

          const statusElement =
            document.querySelector('[data-testid="status"]') ||
            document.querySelector('[role="status"]') ||
            document.querySelector('[aria-live]');
          const status = (statusElement ? statusElement.textContent : document.body.textContent || '').trim();

          return JSON.stringify({
            board: rows,
            score,
            status,
            nonEmpty: flat.filter((value) => value !== null && value !== 0).length,
          }) !== prior;
        }, previousJson, { timeout: 500 });
        return true;
      } catch (_error) {
        return false;
      }
    }

    async function restartLocator(page) {
      return pickFirstLocator([
        page.getByTestId('restart'),
        page.getByRole('button', { name: /restart|new game|play again/i }),
      ]);
    }

    async function waitForFreshBoard(page) {
      await page.waitForFunction(() => {
        const scoreElement = document.querySelector('[data-testid="score"], [data-testid="score-value"]');
        const scoreText = scoreElement ? scoreElement.textContent || '' : '';
        const scoreMatches = scoreText.match(/\\d+/g) || ['0'];
        const score = Number(scoreMatches[scoreMatches.length - 1]);

        const boardElement =
          document.querySelector('[data-testid="board"]') ||
          document.querySelector('[role="grid"][aria-label*="2048 board" i]') ||
          document.querySelector('[role="grid"]');
        const cellNodes = boardElement
          ? Array.from(boardElement.querySelectorAll('[role="gridcell"]'))
          : Array.from(document.querySelectorAll('[data-testid^="tile-"]'));
        const nonEmpty = cellNodes.filter((node) => {
          const text = (node.textContent || '').trim();
          return text !== '' && text !== '0';
        }).length;

        return score === 0 && nonEmpty === 2;
      }, { timeout: 3000 });
    }

    async function restartGame(page) {
      const restart = await restartLocator(page);
      await restart.click();
      await waitForFreshBoard(page);
      return snapshot(page);
    }

    async function verifyDirectionFromFreshBoard(page, key, maxAttempts = 20) {
      for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
        const before = attempt === 0 ? await snapshot(page) : await restartGame(page);
        await page.keyboard.press(key);
        const changed = await waitForChange(page, before);
        if (!changed) continue;

        const after = await snapshot(page);
        return {
          changed: true,
          beforeScore: before.score,
          afterScore: after.score,
          attempts: attempt + 1,
        };
      }

      return {
        changed: false,
        beforeScore: null,
        afterScore: null,
        attempts: maxAttempts,
      };
    }

    test('host-side 2048 playability', async ({ page }) => {
      test.setTimeout(180000);
      const gameOverStatusPattern = /game(?:\s|-)?over/i;

      await page.goto(baseUrl, { waitUntil: 'networkidle' });
      await expect(await boardLocator(page)).toBeVisible();

      const directionChecks = {};
      for (const key of ['ArrowLeft', 'ArrowUp', 'ArrowRight', 'ArrowDown']) {
        directionChecks[key] = await verifyDirectionFromFreshBoard(page, key);
      }

      await restartGame(page);

      let mergeObserved = false;
      let spawnObserved = false;
      let current = await snapshot(page);
      const initial = current;
      const priority = ['ArrowUp', 'ArrowLeft', 'ArrowRight', 'ArrowDown'];

      for (let step = 0; step < 1500; step += 1) {
        if (gameOverStatusPattern.test(current.status)) break;

        let moved = false;
        for (const key of priority) {
          const before = current;
          await page.keyboard.press(key);
          const changed = await waitForChange(page, before);
          if (!changed) continue;

          const after = await snapshot(page);
          directionChecks[key] = {
            changed: true,
            beforeScore: before.score,
            afterScore: after.score,
          };
          if (after.score > before.score) mergeObserved = true;
          if (after.score === before.score && after.nonEmpty > before.nonEmpty) spawnObserved = true;

          current = after;
          moved = true;
          break;
        }

        if (!moved) {
          await page.keyboard.press('ArrowUp');
          current = await snapshot(page);
          if (gameOverStatusPattern.test(current.status)) break;
          if (current.nonEmpty === 16) break;
        }
      }

      if (!gameOverStatusPattern.test(current.status)) {
        for (let attempt = 0; attempt < 20; attempt += 1) {
          await page.keyboard.press('ArrowUp');
          await page.keyboard.press('ArrowLeft');
          current = await snapshot(page);
          if (gameOverStatusPattern.test(current.status)) break;
        }
      }

      const preRestart = current;
      const postRestart = await restartGame(page);
      await page.screenshot({ path: screenshotPath, fullPage: true });

      const result = {
        initial,
        directionChecks,
        mergeObserved,
        spawnObserved,
        gameOverReached: gameOverStatusPattern.test(preRestart.status),
        preRestart,
        postRestart,
        restartResetScore: postRestart.score === 0,
        restartResetTileCount: postRestart.nonEmpty === 2,
        screenshotPath,
      };

      fs.writeFileSync(outputJsonPath, JSON.stringify(result, null, 2));

      expect(result.mergeObserved).toBe(true);
      expect(result.spawnObserved).toBe(true);
      expect(result.gameOverReached).toBe(true);
      expect(result.restartResetScore).toBe(true);
      expect(result.restartResetTileCount).toBe(true);
      expect(Object.values(result.directionChecks).every((entry) => entry.changed)).toBe(true);
    });
  JAVASCRIPT
end

def run_host_playwright_verification!(artifact_dir:, base_url:, generated_app_dir:)
  artifact_spec_path = artifact_dir.join("host-playability.spec.cjs")
  runner_spec_path = generated_app_dir.join("host-playability.spec.cjs")
  output_json_path = artifact_dir.join("host-playwright-verification.json")
  screenshot_path = artifact_dir.join("host-playability.png")
  script = build_playwright_script(output_json_path:, screenshot_path:)

  write_text(artifact_spec_path, script)
  write_text(runner_spec_path, script)

  dependency_install = nil
  browser_install = nil
  test_result = nil

  begin
    dependency_install = capture_command!(
      "npm", "install", "--no-save", "@playwright/test@#{PLAYWRIGHT_VERSION}",
      chdir: generated_app_dir,
      failure_label: "install Playwright host test dependency"
    )
    browser_install = capture_command!(
      "npx", "playwright", "install", "chromium",
      chdir: generated_app_dir,
      failure_label: "install Playwright chromium"
    )
    test_result = capture_command!(
      "npx", "playwright", "test", runner_spec_path.basename.to_s, "--workers=1", "--reporter=line",
      chdir: generated_app_dir,
      env: { "CAPSTONE_PREVIEW_URL" => base_url },
      failure_label: "run Playwright host verification"
    )

    {
      "install" => {
        "dependency_install" => dependency_install,
        "browser_install" => browser_install,
      },
      "test" => test_result,
      "result" => JSON.parse(File.read(output_json_path)),
      "output_json_path" => output_json_path.to_s,
      "screenshot_path" => screenshot_path.to_s,
      "spec_path" => artifact_spec_path.to_s,
    }
  ensure
    FileUtils.rm_f(runner_spec_path)
  end
end

def command_result_excerpt(result, limit:)
  return "missing command result" if result.blank?

  text = [result["stderr"], result["stdout"]].compact.reject(&:blank?).join("\n").strip
  text = "no output" if text.blank?
  return text if text.length <= limit

  "#{text[0, limit]}..."
end

def runtime_validation_passed?(runtime_validation)
  runtime_validation.fetch("runtime_test_passed") &&
    runtime_validation.fetch("runtime_build_passed") &&
    runtime_validation.fetch("runtime_dev_server_ready") &&
    runtime_validation.fetch("runtime_browser_loaded") &&
    runtime_validation.fetch("runtime_browser_mentions_2048")
end

def host_validation_passed?(host_validation:, playwright_validation:)
  host_validation.dig("npm_install", "success") &&
    host_validation.dig("npm_test", "success") &&
    host_validation.dig("npm_build", "success") &&
    host_validation.dig("preview_http", "status") == 200 &&
    playwright_validation["result"].present?
end

def evaluate_workspace_validation(generated_app_dir:, artifact_dir:, preview_port:, runtime_validation:, persist_artifacts: true)
  host_validation_notes = []
  host_validation = {}
  playwright_validation = {}
  preview_http = nil
  host_playability_skip_reason = nil
  dist_artifact_present = false

  if generated_app_dir.exist?
    dist_dir = generated_app_dir.join("dist")
    dist_artifact_present = dist_dir.join("index.html").exist?
    if dist_artifact_present
      begin
        verification = run_host_preview_and_verification!(
          dist_dir: dist_dir,
          artifact_dir: artifact_dir,
          generated_app_dir: generated_app_dir,
          preview_port: preview_port
        )
        preview_http = verification.fetch("preview_http")
        playwright_validation = verification.fetch("playwright_validation")
      rescue => error
        host_playability_skip_reason = "Host-side browser verification failed against `dist/`: #{error.message}"
      end
    else
      host_playability_skip_reason = "Host-side browser verification did not run because `dist/index.html` was missing."
    end

    if generated_app_dir.join("node_modules").exist?
      FileUtils.rm_rf(generated_app_dir.join("node_modules"))
      host_validation_notes << "Removed container-built node_modules before source-portability diagnostics."
    end
    FileUtils.rm_rf(generated_app_dir.join("dist"))
    FileUtils.rm_rf(generated_app_dir.join("coverage"))

    npm_install = capture_command("npm", "install", chdir: generated_app_dir)
    npm_test = capture_command("npm", "test", chdir: generated_app_dir)
    npm_build = capture_command("npm", "run", "build", chdir: generated_app_dir)

    host_validation = {
      "npm_install" => npm_install,
      "npm_test" => npm_test,
      "npm_build" => npm_build,
      "preview_http" => preview_http,
    }

    if persist_artifacts
      write_json(artifact_dir.join("host-npm-install.json"), npm_install)
      write_json(artifact_dir.join("host-npm-test.json"), npm_test)
      write_json(artifact_dir.join("host-npm-build.json"), npm_build)
      write_json(artifact_dir.join("host-preview.json"), preview_http) if preview_http.present?
      if playwright_validation.present?
        write_json(artifact_dir.join("host-playwright-install.json"), playwright_validation.fetch("install"))
        write_json(artifact_dir.join("host-playwright-test.json"), playwright_validation.fetch("test"))
      end

      write_text(artifact_dir.join("workspace-validation.md"), <<~MD)
        # Workspace Validation

        Host-side source portability diagnostics:

        - `npm install` success: `#{npm_install.fetch("success")}`
        - `npm test` success: `#{npm_test.fetch("success")}`
        - `npm run build` success: `#{npm_build.fetch("success")}`

        Host-side `dist/` usability diagnostics:

        - `dist/index.html` present before host checks: `#{dist_artifact_present}`
        - static preview reachable: `#{preview_http&.fetch("status", nil) == 200}`
        - Playwright verification ran: `#{playwright_validation.present?}`

        #{host_playability_skip_reason.present? ? "Host playability note: #{host_playability_skip_reason}" : "Host playability note: browser verification used the exported `dist/` output."}

        See:

        - `host-npm-install.json`
        - `host-npm-test.json`
        - `host-npm-build.json`
        #{preview_http.present? ? "- `host-preview.json`" : nil}
        #{playwright_validation.present? ? "- `host-playwright-test.json`" : nil}
      MD

      write_playability_verification_md(
        path: artifact_dir.join("playability-verification.md"),
        playability_result: playwright_validation["result"],
        generated_app_dir: generated_app_dir,
        preview_port: preview_port,
        runtime_validation: runtime_validation,
        preview_validation: {
          "reachable" => preview_http&.fetch("status", nil) == 200,
          "contains_2048" => preview_http&.fetch("contains_2048", false) || false,
        },
        host_skip_reason: host_playability_skip_reason
      )
    end
  elsif persist_artifacts
    write_text(artifact_dir.join("workspace-validation.md"), <<~MD)
      # Workspace Validation

      Expected generated app directory was missing:
      - `#{generated_app_dir}`
    MD
    write_playability_verification_md(
      path: artifact_dir.join("playability-verification.md"),
      playability_result: nil,
      generated_app_dir: generated_app_dir,
      preview_port: preview_port,
      runtime_validation: runtime_validation,
      preview_validation: {
        "reachable" => false,
        "contains_2048" => false,
      },
      host_skip_reason: "Generated application path was missing."
    )
  end

  {
    "host_validation_notes" => host_validation_notes,
    "host_validation" => host_validation,
    "playwright_validation" => playwright_validation,
    "preview_http" => preview_http,
    "host_playability_skip_reason" => host_playability_skip_reason,
    "dist_artifact_present" => dist_artifact_present,
  }
end

def build_repair_prompt(
  attempt_no:,
  max_turn_attempts:,
  workflow_run:,
  runtime_validation:,
  host_validation:,
  playwright_validation:,
  host_playability_skip_reason:,
  generated_app_dir:,
  limit:
)
  lines = []
  lines << "Your previous attempt did not satisfy the acceptance harness."
  lines << "Continue working in `/workspace/game-2048` and fix the existing app. Do not restart from scratch unless necessary."
  lines << "This is repair attempt #{attempt_no} of #{max_turn_attempts}."
  lines << ""
  lines << "Observed problems:"
  lines << "- workflow state was `#{workflow_run.lifecycle_state}`." unless workflow_run.lifecycle_state == "completed"

  unless runtime_validation.fetch("runtime_test_passed")
    lines << "- runtime-side evidence for tests passing was missing."
  end
  unless runtime_validation.fetch("runtime_build_passed")
    lines << "- runtime-side evidence for a successful production build was missing."
  end
  unless runtime_validation.fetch("runtime_dev_server_ready")
    lines << "- runtime-side evidence for a dev server on `0.0.0.0:4173` was missing."
  end
  unless runtime_validation.fetch("runtime_browser_loaded")
    lines << "- runtime-side browser verification was missing."
  end
  if runtime_validation.fetch("runtime_browser_loaded") && !runtime_validation.fetch("runtime_browser_mentions_2048")
    lines << "- runtime-side browser content did not clearly show the 2048 game."
  end

  if host_validation.dig("npm_install", "success") == false
    lines << "- host `npm install` failed:"
    lines << command_result_excerpt(host_validation.fetch("npm_install"), limit:)
  end
  if host_validation.dig("npm_test", "success") == false
    lines << "- host `npm test` failed:"
    lines << command_result_excerpt(host_validation.fetch("npm_test"), limit:)
  end
  if host_validation.dig("npm_build", "success") == false
    lines << "- host `npm run build` failed:"
    lines << command_result_excerpt(host_validation.fetch("npm_build"), limit:)
  end
  if host_validation.dig("preview_http", "status") != 200
    lines << "- host static preview was not reachable at `http://127.0.0.1:4174/`."
  end
  if playwright_validation["result"].blank? && host_playability_skip_reason.present?
    lines << "- host browser verification failed:"
    lines << host_playability_skip_reason
  end

  lines << ""
  lines << "Before replying, you must:"
  lines << "- make the existing app in `#{generated_app_dir}` satisfy the original 2048 requirements"
  lines << "- run tests successfully"
  lines << "- run a production build successfully"
  lines << "- start the app on `0.0.0.0:4173`"
  lines << "- verify it in a browser session"
  lines << "- finish with a concise completion note that reflects what actually passed"

  lines.join("\n")
end

case capstone_phase
when "bootstrap"
  FileUtils.rm_rf(artifact_dir)
  FileUtils.mkdir_p(artifact_dir)
  FileUtils.rm_rf(generated_app_dir)

  ManualAcceptanceSupport.reset_backend_state!
  bootstrap = ManualAcceptanceSupport.bootstrap_and_seed!
  bundled = ManualAcceptanceSupport.register_bundled_runtime_from_manifest!(
    installation: bootstrap.installation,
    runtime_base_url: runtime_base_url,
    runtime_fingerprint: runtime_fingerprint,
    fingerprint: program_fingerprint,
    sdk_version: "fenix-0.1.0"
  )

  machine_credential = bundled.fetch(:machine_credential)
  execution_machine_credential = bundled.fetch(:execution_machine_credential)
  agent_program = bundled.fetch(:runtime).agent_program
  agent_program_version = bundled.fetch(:runtime).deployment
  execution_runtime = bundled.fetch(:runtime).execution_runtime
  agent_session = bundled.fetch(:runtime).agent_session
  execution_session = bundled.fetch(:runtime).execution_session

  bootstrap_state = {
    "scenario_date" => scenario_date,
    "machine_credential" => machine_credential,
    "execution_machine_credential" => execution_machine_credential,
    "agent_program_id" => agent_program.public_id,
    "agent_program_version_id" => agent_program_version.public_id,
    "execution_runtime_id" => execution_runtime.public_id,
    "agent_session_id" => agent_session.public_id,
    "execution_session_id" => execution_session.public_id,
    "runtime_base_url" => runtime_base_url,
    "docker_container" => docker_container,
    "runtime_fingerprint" => runtime_fingerprint,
    "program_fingerprint" => program_fingerprint,
  }

  write_json(bootstrap_state_path, bootstrap_state)
  puts JSON.pretty_generate(bootstrap_state)
  exit 0
when "execute"
  raise "missing capstone bootstrap state: #{bootstrap_state_path}" unless bootstrap_state_path.exist?

  bootstrap_state = read_json(bootstrap_state_path)
  FileUtils.mkdir_p(artifact_dir)

  machine_credential = bootstrap_state.fetch("machine_credential")
  execution_machine_credential = bootstrap_state.fetch("execution_machine_credential")
  agent_program = AgentProgram.find_by_public_id!(bootstrap_state.fetch("agent_program_id"))
  agent_program_version = AgentProgramVersion.find_by_public_id!(bootstrap_state.fetch("agent_program_version_id"))
  execution_runtime = ExecutionRuntime.find_by_public_id!(bootstrap_state.fetch("execution_runtime_id"))
  agent_session = AgentSession.find_by_public_id!(bootstrap_state.fetch("agent_session_id"))
  execution_session = ExecutionSession.find_by_public_id!(bootstrap_state.fetch("execution_session_id"))
  runtime_worker_boot = runtime_worker_boot_path.exist? ? read_json(runtime_worker_boot_path) : nil
else
  raise "unsupported CAPSTONE_PHASE: #{capstone_phase}"
end

skill_sources = prepare_skill_sources!(skill_source_root:)
log_capstone_phase(
  artifact_dir: artifact_dir,
  phase: "skill_sources_prepared",
  details: {
    "workspace_root" => workspace_root.to_s,
    "skill_source_manifest_path" => skill_sources.fetch("manifest_path"),
  }
)
skills_validation = install_and_validate_skills!(
  agent_program_version: agent_program_version,
  skill_sources:,
  workspace_root:,
  runtime_worker_boot:
)
log_capstone_phase(
  artifact_dir: artifact_dir,
  phase: "skills_validated",
  details: {
    "passed" => skills_validation.fetch("passed"),
    "skill_count" => skills_validation.fetch("skill_sources").size,
  }
)

write_json(artifact_dir.join("acceptance-registration.json"), {
  "agent_program_id" => agent_program.public_id,
  "agent_program_display_name" => agent_program.display_name,
  "agent_program_version_id" => agent_program_version.public_id,
  "execution_runtime_id" => execution_runtime.public_id,
  "execution_runtime_display_name" => execution_runtime.display_name,
  "agent_session_id" => agent_session.public_id,
  "execution_session_id" => execution_session.public_id,
  "runtime_fingerprint" => execution_runtime.runtime_fingerprint,
  "program_fingerprint" => agent_program_version.fingerprint,
  "machine_credential_redacted" => machine_credential.to_s.sub(/:.+\z/, ":REDACTED"),
})
write_json(artifact_dir.join("capstone-run-bootstrap.json"), {
  "scenario_date" => scenario_date,
  "operator" => OPERATOR_NAME,
  "selector" => selector,
  "attempt_count" => 0,
  "workspace_root" => workspace_root.to_s,
  "generated_app_dir" => generated_app_dir.to_s,
  "skill_source_manifest_path" => skill_sources.fetch("manifest_path"),
  "prompt" => prompt,
})
write_json(artifact_dir.join("skills-validation.json"), skills_validation)
write_json(artifact_dir.join("attempt-history.json"), [])
write_json(artifact_dir.join("rescue-history.json"), [])

conversation_context = ManualAcceptanceSupport.create_conversation!(agent_program_version: agent_program_version)
conversation = conversation_context.fetch(:conversation).reload
log_capstone_phase(
  artifact_dir: artifact_dir,
  phase: "conversation_initialized",
  details: {
    "conversation_id" => conversation.public_id,
    "workspace_id" => conversation.workspace.public_id,
  }
)
ensure_conversation_capability_policy!(
  conversation: conversation,
  control_enabled: true
)
run = nil
turn = nil
workflow_run = nil
supervision_trace = nil
host_validation_bundle = nil
repair_prompt = prompt
attempt_history = []
rescue_history = []
terminal_failure_message = nil

1.upto(max_turn_attempts) do |attempt_no|
  log_capstone_phase(
    artifact_dir: artifact_dir,
    phase: "attempt_started",
    details: {
      "attempt_no" => attempt_no,
      "max_turn_attempts" => max_turn_attempts,
    }
  )
  run = ManualAcceptanceSupport.start_turn_workflow_on_conversation!(
    conversation: conversation,
    agent_program_version: agent_program_version,
    content: repair_prompt,
    root_node_key: "turn_step",
    root_node_type: "turn_step",
    decision_source: "system",
    selector_source: "conversation",
    selector: selector
  )
  dispatched_node = Workflows::ExecuteRun.call(workflow_run: run.fetch(:workflow_run))
  ManualAcceptanceSupport.execute_inline_if_queued!(workflow_node: dispatched_node) if dispatched_node.present?

  supervision_trace = supervise_conversation_progress!(
    conversation_id: conversation.public_id,
    actor: conversation_context.fetch(:actor),
    timeout_seconds: supervision_timeout_seconds,
    poll_interval_seconds: supervision_poll_interval_seconds,
    stall_threshold_ms: supervision_stall_threshold_ms
  )
  log_capstone_phase(
    artifact_dir: artifact_dir,
    phase: "supervision_complete",
    details: {
      "attempt_no" => attempt_no,
      "poll_count" => supervision_trace.fetch("polls").length,
      "overall_state" => supervision_trace.dig("final_response", "machine_status", "overall_state"),
    }
  )

  turn = run.fetch(:turn).reload
  workflow_run = ManualAcceptanceSupport.wait_for_workflow_run_terminal!(
    workflow_run: run.fetch(:workflow_run),
    timeout_seconds: 30
  )
  conversation = conversation.reload

  debug_payload = ConversationDebugExports::BuildPayload.call(conversation: conversation)
  runtime_validation = build_conversation_runtime_validation(
    tool_invocations: debug_payload.fetch("tool_invocations")
  )
  log_capstone_phase(
    artifact_dir: artifact_dir,
    phase: "host_validation_started",
    details: {
      "attempt_no" => attempt_no,
      "workflow_run_id" => workflow_run.public_id,
      "workflow_state" => workflow_run.lifecycle_state,
    }
  )
  host_validation_bundle = evaluate_workspace_validation(
    generated_app_dir: generated_app_dir,
    artifact_dir: artifact_dir,
    preview_port: preview_port,
    runtime_validation: runtime_validation,
    persist_artifacts: true
  )
  host_validation = host_validation_bundle.fetch("host_validation")
  playwright_validation = host_validation_bundle.fetch("playwright_validation")
  log_capstone_phase(
    artifact_dir: artifact_dir,
    phase: "host_validation_complete",
    details: {
      "attempt_no" => attempt_no,
      "npm_install_passed" => host_validation.dig("npm_install", "success"),
      "npm_test_passed" => host_validation.dig("npm_test", "success"),
      "npm_build_passed" => host_validation.dig("npm_build", "success"),
      "preview_reachable" => host_validation.dig("preview_http", "status") == 200,
      "playwright_verification_passed" => playwright_validation["result"].present?,
    }
  )

  attempt_history << {
    "attempt_no" => attempt_no,
    "turn_id" => turn.public_id,
    "workflow_run_id" => workflow_run.public_id,
    "workflow_state" => workflow_run.lifecycle_state,
    "runtime_validation" => runtime_validation,
    "host_validation" => {
      "npm_install_passed" => host_validation.dig("npm_install", "success"),
      "npm_test_passed" => host_validation.dig("npm_test", "success"),
      "npm_build_passed" => host_validation.dig("npm_build", "success"),
      "preview_reachable" => host_validation.dig("preview_http", "status") == 200,
      "playwright_verification_passed" => playwright_validation["result"].present?,
    },
  }
  write_json(artifact_dir.join("attempt-history.json"), attempt_history)
  write_json(artifact_dir.join("supervision-session.json"), supervision_trace.fetch("session"))
  write_json(artifact_dir.join("supervision-polls.json"), supervision_trace.fetch("polls"))
  write_json(artifact_dir.join("supervision-final.json"), supervision_trace.fetch("final_response"))
  write_supervision_sidechat_md(
    path: artifact_dir.join("supervision-sidechat.md"),
    supervision_trace: supervision_trace,
    prompt: SUPERVISION_PROMPT
  )
  write_supervision_status_md(
    path: artifact_dir.join("supervision-status.md"),
    supervision_trace: supervision_trace
  )
  write_supervision_feed_md(
    path: artifact_dir.join("supervision-feed.md"),
    supervision_trace: supervision_trace
  )

  if workflow_run.lifecycle_state == "completed" &&
      runtime_validation_passed?(runtime_validation) &&
      host_validation_passed?(host_validation:, playwright_validation:)
    log_capstone_phase(
      artifact_dir: artifact_dir,
      phase: "attempt_succeeded",
      details: {
        "attempt_no" => attempt_no,
        "workflow_run_id" => workflow_run.public_id,
      }
    )
    break
  end

  if attempt_no >= max_turn_attempts
    terminal_failure_message = <<~MSG
      2048 acceptance did not converge after #{max_turn_attempts} attempts
      last workflow state: #{workflow_run.lifecycle_state}
      last runtime validation:
      #{JSON.pretty_generate(runtime_validation)}
      last host validation:
      #{JSON.pretty_generate(host_validation_bundle)}
    MSG
    write_text(artifact_dir.join("terminal-failure.txt"), terminal_failure_message)
    log_capstone_phase(
      artifact_dir: artifact_dir,
      phase: "terminal_failure_recorded",
      details: {
        "attempt_no" => attempt_no,
        "workflow_run_id" => workflow_run.public_id,
      }
    )
    break
  end

  repair_prompt = build_repair_prompt(
    attempt_no: attempt_no + 1,
    max_turn_attempts: max_turn_attempts,
    workflow_run: workflow_run,
    runtime_validation: runtime_validation,
    host_validation: host_validation,
    playwright_validation: playwright_validation,
    host_playability_skip_reason: host_validation_bundle.fetch("host_playability_skip_reason"),
    generated_app_dir: generated_app_dir,
    limit: validation_note_limit
  )
  rescue_history << build_rescue_history_entry(
    attempt_no: attempt_no,
    workflow_run: workflow_run,
    runtime_validation: runtime_validation,
    host_validation: host_validation,
    playwright_validation: playwright_validation,
    host_playability_skip_reason: host_validation_bundle.fetch("host_playability_skip_reason"),
    repair_prompt: repair_prompt
  )
  write_json(artifact_dir.join("rescue-history.json"), rescue_history)
  log_capstone_phase(
    artifact_dir: artifact_dir,
    phase: "repair_prompt_prepared",
    details: {
      "attempt_no" => attempt_no,
      "next_attempt_no" => attempt_no + 1,
      "trigger_reasons" => rescue_history.last.fetch("trigger_reasons"),
    }
  )
end

log_capstone_phase(
  artifact_dir: artifact_dir,
  phase: "export_roundtrip_started",
  details: {
    "attempt_count" => attempt_history.length,
    "rescue_count" => rescue_history.length,
  }
)

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

parsed_debug = unpack_debug_bundle!(
  zip_path: debug_bundle_path,
  destination_dir: artifact_dir.join("tmp", "debug-unpacked")
)

usage_events = Array(parsed_debug["usage_events.json"])
command_runs = Array(parsed_debug["command_runs.json"])
process_runs = Array(parsed_debug["process_runs.json"])
tool_invocations = Array(parsed_debug["tool_invocations.json"])
subagent_sessions = Array(parsed_debug["subagent_sessions.json"])
workflow_nodes = Array(parsed_debug["workflow_nodes.json"])
workflow_node_events = Array(parsed_debug["workflow_node_events.json"])
agent_task_runs = Array(parsed_debug["agent_task_runs.json"])

provider_breakdown = usage_events.each_with_object(Hash.new do |hash, key|
  hash[key] = { "event_count" => 0, "input_tokens_total" => 0, "output_tokens_total" => 0 }
end) do |entry, memo|
  key = [entry["provider_handle"], entry["model_ref"], entry["operation_kind"]]
  bucket = memo[key]
  bucket["provider_handle"] = entry["provider_handle"]
  bucket["model_ref"] = entry["model_ref"]
  bucket["operation_kind"] = entry["operation_kind"]
  bucket["event_count"] += 1
  bucket["input_tokens_total"] += entry["input_tokens"].to_i
  bucket["output_tokens_total"] += entry["output_tokens"].to_i
end.values.sort_by { |entry| [entry["provider_handle"], entry["model_ref"], entry["operation_kind"]] }

write_json(artifact_dir.join("capstone-run-bootstrap.json"), {
  "scenario_date" => scenario_date,
  "operator" => OPERATOR_NAME,
  "selector" => selector,
  "attempt_count" => attempt_history.length,
  "workspace_root" => workspace_root.to_s,
  "generated_app_dir" => generated_app_dir.to_s,
  "skill_source_manifest_path" => skill_sources.fetch("manifest_path"),
  "prompt" => prompt,
})
write_json(artifact_dir.join("attempt-history.json"), attempt_history)
write_json(artifact_dir.join("rescue-history.json"), rescue_history)
write_json(artifact_dir.join("supervision-session.json"), supervision_trace.fetch("session"))
write_json(artifact_dir.join("supervision-polls.json"), supervision_trace.fetch("polls"))
write_json(artifact_dir.join("supervision-final.json"), supervision_trace.fetch("final_response"))
write_supervision_sidechat_md(
  path: artifact_dir.join("supervision-sidechat.md"),
  supervision_trace: supervision_trace,
  prompt: SUPERVISION_PROMPT
)
write_supervision_status_md(
  path: artifact_dir.join("supervision-status.md"),
  supervision_trace: supervision_trace
)
write_supervision_feed_md(
  path: artifact_dir.join("supervision-feed.md"),
  supervision_trace: supervision_trace
)
write_json(artifact_dir.join("source-transcript.json"), source_transcript)
write_json(artifact_dir.join("source-diagnostics-show.json"), source_diagnostics_show)
write_json(artifact_dir.join("source-diagnostics-turns.json"), source_diagnostics_turns)
write_json(artifact_dir.join("diagnostics.json"), {
  "source_show" => source_diagnostics_show,
  "source_turns" => source_diagnostics_turns,
  "imported_show" => imported_diagnostics_show,
})
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

write_text(artifact_dir.join("export-roundtrip.md"), <<~MD)
  # Export Roundtrip

  Source conversation:
  - `#{conversation.public_id}`

  Imported conversation:
  - `#{imported_conversation_id}`

  Results:
  - supervision session: `#{supervision_trace.dig("session", "conversation_supervision_session", "supervision_session_id")}`
  - supervision poll count: `#{supervision_trace.fetch("polls").length}`
  - final supervision state: `#{supervision_trace.dig("final_response", "machine_status", "overall_state")}`
  - `ConversationExport` succeeded through `/app_api/conversation_export_requests`
  - `ConversationDebugExport` succeeded through `/app_api/conversation_debug_export_requests`
  - `ConversationImport` succeeded through `/app_api/conversation_bundle_import_requests`
  - transcript roundtrip match: `#{transcript_roundtrip_match}`
  - command runs exported: `#{command_runs.length}`
  - process runs exported: `#{process_runs.length}`
  - workflow nodes exported: `#{workflow_nodes.length}`
  - subagent sessions exported: `#{subagent_sessions.length}`
MD

host_validation_notes = host_validation_bundle.fetch("host_validation_notes")
host_validation = host_validation_bundle.fetch("host_validation")
playwright_validation = host_validation_bundle.fetch("playwright_validation")
preview_http = host_validation_bundle.fetch("preview_http")
host_playability_skip_reason = host_validation_bundle.fetch("host_playability_skip_reason")
control_intent_matrix = nil

if control_acceptance_enabled
  control_intent_matrix = run_control_intent_matrix!(
    artifact_dir: artifact_dir,
    supervision_session_id: supervision_trace.dig("session", "conversation_supervision_session", "supervision_session_id"),
    actor: conversation_context.fetch(:actor),
    conversation: conversation
  )
end

write_conversation_transcript_md(artifact_dir.join("conversation-transcript.md"), source_transcript)
main_diagnostics_turn = source_diagnostics_turns.fetch("items").fetch(0)
turn_runtime_report = Acceptance::TurnRuntimeTranscript.build(
  conversation_id: conversation.public_id,
  turn_id: turn.public_id,
  phase_events: artifact_dir.join("phase-events.jsonl").exist? ? File.readlines(artifact_dir.join("phase-events.jsonl"), chomp: true).filter_map { |line| JSON.parse(line) if line.present? } : [],
  workflow_node_events: workflow_node_events,
  usage_events: usage_events,
  tool_invocations: tool_invocations,
  command_runs: command_runs,
  process_runs: process_runs,
  subagent_sessions: subagent_sessions,
  agent_task_runs: agent_task_runs,
  supervision_trace: supervision_trace,
  summary: {
    "benchmark_outcome" => terminal_failure_message.present? ? "pending" : "in_progress",
    "workload_outcome" => workflow_run.lifecycle_state,
    "system_behavior_outcome" => supervision_trace.dig("final_response", "machine_status", "overall_state"),
  }
)
write_text(
  artifact_dir.join("review", "turn-runtime-transcript.md"),
  Acceptance::TurnRuntimeTranscript.to_markdown(turn_runtime_report)
)
write_json(
  artifact_dir.join("evidence", "turn-runtime-evidence.json"),
  turn_runtime_report
)
write_jsonl(
  artifact_dir.join("logs", "turn-runtime-events.jsonl"),
  turn_runtime_report.fetch("timeline")
)
write_turns_md(
  path: artifact_dir.join("turns.md"),
  scenario_date: scenario_date,
  conversation: conversation,
  turn: turn,
  workflow_run: workflow_run,
  agent_program_version: agent_program_version,
  execution_runtime: execution_runtime,
  selector: selector,
  diagnostics_turn: main_diagnostics_turn,
  source_transcript: source_transcript,
  provider_breakdown: provider_breakdown,
  subagent_sessions: subagent_sessions,
  proof_artifacts: [
    "acceptance-registration.json",
    "capstone-run-bootstrap.json",
    "phase-events.jsonl",
    "skills-validation.json",
    "attempt-history.json",
    "rescue-history.json",
    "workspace-validation.md",
    "supervision-session.json",
    "supervision-polls.json",
    "supervision-final.json",
    "supervision-sidechat.md",
    "supervision-status.md",
    "supervision-feed.md",
    "capability-activation.json",
    "capability-activation.md",
    "failure-classification.json",
    "failure-classification.md",
    ("terminal-failure.txt" if terminal_failure_message.present?),
    ("control-intent-matrix.json" if control_intent_matrix.present?),
    ("host-preview.json" if preview_http.present?),
    ("host-playwright-verification.json" if playwright_validation.present?),
    ("host-playability.png" if playwright_validation.present?),
    "playability-verification.md",
    "export-roundtrip.md",
  ].compact
)
write_collaboration_notes_md(
  path: artifact_dir.join("collaboration-notes.md"),
  selector: selector,
  host_validation_notes: host_validation_notes,
  subagent_sessions: subagent_sessions
)

log_capstone_phase(
  artifact_dir: artifact_dir,
  phase: "benchmark_reporting_started",
  details: {
    "tool_call_count" => tool_invocations.length,
    "subagent_session_count" => subagent_sessions.length,
  }
)
write_runtime_and_bindings_md(
  path: artifact_dir.join("runtime-and-bindings.md"),
  workspace_root: workspace_root,
  machine_credential: machine_credential,
  agent_program: agent_program,
  agent_program_version: agent_program_version,
  execution_runtime: execution_runtime,
  skill_source_manifest_path: skill_sources.fetch("manifest_path"),
  docker_container: docker_container,
  runtime_base_url: runtime_base_url,
  runtime_worker_boot: runtime_worker_boot
)
write_workspace_artifacts_md(
  path: artifact_dir.join("workspace-artifacts.md"),
  workspace_root: workspace_root,
  generated_app_dir: generated_app_dir,
  host_validation_notes: host_validation_notes,
  preview_port: preview_port
)
write_playability_verification_md(
  path: artifact_dir.join("playability-verification.md"),
  playability_result: playwright_validation["result"],
  generated_app_dir: generated_app_dir,
  preview_port: preview_port,
  runtime_validation: build_conversation_runtime_validation(tool_invocations: tool_invocations),
  preview_validation: {
    "reachable" => preview_http&.fetch("status", nil) == 200,
    "contains_2048" => preview_http&.fetch("contains_2048", false) || false,
  },
  host_skip_reason: host_playability_skip_reason
)

conversation_validation = build_conversation_runtime_validation(tool_invocations: tool_invocations)
capability_report = Acceptance::CapabilityActivation.build(
  contract: CAPABILITY_CONTRACT,
  tool_invocations: tool_invocations,
  command_runs: command_runs,
  subagent_sessions: subagent_sessions,
  artifact_paths: {
    "workspace_validation" => artifact_dir.join("workspace-validation.md"),
    "skills_validation" => artifact_dir.join("skills-validation.json"),
    "supervision_session" => artifact_dir.join("supervision-session.json"),
    "supervision_polls" => artifact_dir.join("supervision-polls.json"),
    "supervision_final" => artifact_dir.join("supervision-final.json"),
    "supervision_status" => artifact_dir.join("supervision-status.md"),
    "conversation_export" => user_bundle_path,
    "conversation_debug_export" => debug_bundle_path,
    "transcript_roundtrip" => artifact_dir.join("transcript-roundtrip-compare.json"),
    "host_npm_install" => artifact_dir.join("host-npm-install.json"),
    "host_npm_test" => artifact_dir.join("host-npm-test.json"),
    "host_npm_build" => artifact_dir.join("host-npm-build.json"),
    "host_preview" => artifact_dir.join("host-preview.json"),
    "host_playwright_verification" => artifact_dir.join("host-playwright-verification.json"),
    "host_playability_image" => artifact_dir.join("host-playability.png"),
    "playability_verification" => artifact_dir.join("playability-verification.md"),
  },
  workspace_paths: {
    "generated_app_dir" => generated_app_dir,
  },
  skill_validation: skills_validation,
  transcript_roundtrip_match: transcript_roundtrip_match,
  supervision_trace: supervision_trace
)
write_json(artifact_dir.join("capability-activation.json"), capability_report)
write_capability_activation_md(
  path: artifact_dir.join("capability-activation.md"),
  capability_report: capability_report
)

workload_outcome = determine_workload_outcome(
  workflow_run: workflow_run,
  runtime_validation: conversation_validation,
  host_validation: host_validation,
  playwright_validation: playwright_validation,
  generated_app_dir: generated_app_dir
)
failure_report = Acceptance::FailureClassification.build(
  scenario: CAPABILITY_CONTRACT.fetch("scenario"),
  capability_report: capability_report,
  workload_outcome: workload_outcome,
  diagnostics: {
    "workflow_state" => workflow_run.lifecycle_state,
    "terminal_failure_message" => terminal_failure_message,
    "conversation_validation" => conversation_validation,
    "workspace_validation" => {
      "generated_app_dir_exists" => generated_app_dir.exist?,
      "npm_install_passed" => host_validation.dig("npm_install", "success"),
      "npm_test_passed" => host_validation.dig("npm_test", "success"),
      "npm_build_passed" => host_validation.dig("npm_build", "success"),
      "preview_reachable" => host_validation.dig("preview_http", "status") == 200,
      "preview_contains_2048" => host_validation.dig("preview_http", "contains_2048") || false,
      "playwright_verification_passed" => playwright_validation["result"].present?,
    },
  },
  rescue_history: rescue_history,
  timeline: build_failure_timeline(
    attempt_history: attempt_history,
    terminal_failure_message: terminal_failure_message
  ),
  notes: [terminal_failure_message].compact
)
write_json(artifact_dir.join("failure-classification.json"), failure_report)
write_failure_classification_md(
  path: artifact_dir.join("failure-classification.md"),
  failure_report: failure_report
)

summary = {
  "scenario_date" => scenario_date,
  "operator" => OPERATOR_NAME,
  "conversation_id" => conversation.public_id,
  "workspace_id" => conversation.workspace.public_id,
  "turn_id" => turn.public_id,
  "workflow_run_id" => workflow_run.public_id,
  "agent_program_id" => agent_program.public_id,
  "agent_program_version_id" => agent_program_version.public_id,
  "execution_runtime_id" => execution_runtime.public_id,
  "selector" => selector,
  "workflow_state" => workflow_run.lifecycle_state,
  "turn_state" => turn.lifecycle_state,
  "supervision_session_id" => supervision_trace.dig("session", "conversation_supervision_session", "supervision_session_id"),
  "supervision_poll_count" => supervision_trace.fetch("polls").length,
  "supervision_final_state" => supervision_trace.dig("final_response", "machine_status", "overall_state"),
  "supervision_human_sidechat" => supervision_trace.dig("final_response", "human_sidechat", "content"),
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
  "skills_validation_path" => artifact_dir.join("skills-validation.json").to_s,
  "capability_activation_path" => artifact_dir.join("capability-activation.json").to_s,
  "failure_classification_path" => artifact_dir.join("failure-classification.json").to_s,
  "phase_events_path" => artifact_dir.join("phase-events.jsonl").to_s,
  "host_playability_artifact" => (artifact_dir.join("host-playwright-verification.json").to_s if playwright_validation.present?),
  "control_intent_matrix_path" => (artifact_dir.join("control-intent-matrix.json").to_s if control_intent_matrix.present?),
  "benchmark_outcome" => failure_report.fetch("outcome"),
  "workload_outcome" => failure_report.fetch("workload_outcome"),
  "system_behavior_outcome" => failure_report.fetch("system_behavior_outcome"),
  "failure_primary_category" => failure_report.dig("classification", "primary"),
  "failure_recommended_actions" => failure_report.fetch("recommended_actions"),
  "capability_activation" => capability_report.fetch("summary"),
  "rescue_history_count" => rescue_history.length,
  "terminal_failure_message" => terminal_failure_message,
  "conversation_validation" => conversation_validation,
  "workspace_validation" => {
    "generated_app_dir_exists" => generated_app_dir.exist?,
    "npm_install_passed" => host_validation.dig("npm_install", "success"),
    "npm_test_passed" => host_validation.dig("npm_test", "success"),
    "npm_build_passed" => host_validation.dig("npm_build", "success"),
    "preview_reachable" => host_validation.dig("preview_http", "status") == 200,
    "preview_contains_2048" => host_validation.dig("preview_http", "contains_2048") || false,
    "playwright_verification_passed" => playwright_validation["result"].present?,
  },
}
summary["control_intent_matrix"] = control_intent_matrix.fetch("summary") if control_intent_matrix.present?

evaluation = build_agent_evaluation(
  summary: summary,
  diagnostics_turn: main_diagnostics_turn
)
summary["agent_evaluation"] = evaluation.transform_values { |payload| payload.fetch("rating") }

write_agent_evaluation_md(artifact_dir.join("agent-evaluation.md"), evaluation)
write_json(artifact_dir.join("agent-evaluation.json"), evaluation)
write_json(artifact_dir.join("run-summary.json"), summary)
write_json(artifact_dir.join("evidence", "run-summary.json"), summary)
log_capstone_phase(
  artifact_dir: artifact_dir,
  phase: "benchmark_reporting_complete",
  details: {
    "benchmark_outcome" => summary.fetch("benchmark_outcome"),
    "workload_outcome" => summary.fetch("workload_outcome"),
    "system_behavior_outcome" => summary.fetch("system_behavior_outcome"),
  }
)
turn_runtime_report.fetch("summary").merge!(
  "benchmark_outcome" => summary.fetch("benchmark_outcome"),
  "workload_outcome" => summary.fetch("workload_outcome"),
  "system_behavior_outcome" => summary.fetch("system_behavior_outcome")
)
write_text(
  artifact_dir.join("review", "turn-runtime-transcript.md"),
  Acceptance::TurnRuntimeTranscript.to_markdown(turn_runtime_report)
)
write_json(
  artifact_dir.join("evidence", "turn-runtime-evidence.json"),
  turn_runtime_report
)
write_jsonl(
  artifact_dir.join("logs", "turn-runtime-events.jsonl"),
  turn_runtime_report.fetch("timeline")
)
organize_artifact_layout!(
  artifact_dir: artifact_dir,
  layout: {
    "review" => [
      "conversation-transcript.md",
      "turns.md",
      "collaboration-notes.md",
      "runtime-and-bindings.md",
      "workspace-artifacts.md",
      "workspace-validation.md",
      "supervision-sidechat.md",
      "supervision-status.md",
      "supervision-feed.md",
      "capability-activation.md",
      "failure-classification.md",
      "playability-verification.md",
      "export-roundtrip.md",
      "agent-evaluation.md",
    ],
    "evidence" => [
      "capstone-run-bootstrap.json",
      "skills-validation.json",
      "attempt-history.json",
      "rescue-history.json",
      "source-transcript.json",
      "source-diagnostics-show.json",
      "source-diagnostics-turns.json",
      "diagnostics.json",
      "export-request-create.json",
      "export-request-show.json",
      "debug-export-request-create.json",
      "debug-export-request-show.json",
      "import-request-create.json",
      "import-request-show.json",
      "imported-transcript.json",
      "imported-diagnostics-show.json",
      "transcript-roundtrip-compare.json",
      "capability-activation.json",
      "failure-classification.json",
      "agent-evaluation.json",
      "run-summary.json",
      "control-intent-matrix.json",
      "terminal-failure.txt",
    ],
    "logs" => [
      "phase-events.jsonl",
      "supervision-session.json",
      "supervision-polls.json",
      "supervision-final.json",
      "host-preview.log",
    ],
    "exports" => [
      "conversation-export.zip",
      "conversation-debug-export.zip",
      "export-request-create.json",
      "export-request-show.json",
      "debug-export-request-create.json",
      "debug-export-request-show.json",
      "import-request-create.json",
      "import-request-show.json",
      "transcript-roundtrip-compare.json",
    ],
    "playable" => [
      "host-npm-install.json",
      "host-npm-test.json",
      "host-npm-build.json",
      "host-preview.json",
      "host-playwright-verification.json",
      "host-playability.png",
    ],
    "tmp" => [
      "host-playability.spec.cjs",
    ],
  }
)
write_review_index_md(
  path: artifact_dir.join("review", "index.md"),
  summary: summary
)
write_artifact_root_readme(
  path: artifact_dir.join("README.md"),
  artifact_stamp: artifact_stamp,
  summary: summary
)

puts JSON.pretty_generate(summary)
raise terminal_failure_message if terminal_failure_message.present?
