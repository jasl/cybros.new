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
require "set"
require_relative "../lib/boot"
require_relative "../lib/conversation_control_phrase_matrix"
require_relative "../lib/conversation_runtime_validation"

$stdout.sync = true
$stderr.sync = true

OPERATOR_NAME = "Codex".freeze
RUNTIME_MODE = "Core Matrix host runtime + Dockerized Fenix".freeze
EXPECTED_SKILL_DAG_SHAPE = ["agent_turn_step"].freeze
SUPERVISION_PROMPT = "Please tell me what you are doing right now and what changed most recently.".freeze
TERMINAL_WORK_SEGMENT_STATES = %w[completed failed interrupted canceled].freeze
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
bootstrap_state_path = Pathname.new(ENV.fetch("CAPSTONE_BOOTSTRAP_STATE_PATH", artifact_dir.join("evidence", "capstone-runtime-bootstrap.json").to_s))
runtime_worker_boot_path = Pathname.new(ENV.fetch("CAPSTONE_RUNTIME_WORKER_BOOT_PATH", artifact_dir.join("evidence", "docker-runtime-worker.json").to_s))
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
- expose a game-over status through `data-testid="status"` that visibly contains the words `Game over` when no moves remain
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

def log_capstone_phase(artifact_dir:, phase:, details: {})
  payload = {
    "timestamp" => Time.current.iso8601,
    "phase" => phase,
  }.merge(details.transform_keys(&:to_s))

  append_jsonl(artifact_dir.join("logs", "phase-events.jsonl"), payload)
  puts "[capstone] #{JSON.generate(payload)}"
end

def read_json(path)
  JSON.parse(File.read(path))
end

def assert_2048_bundle_quality_contract!(artifact_dir:)
  status_markdown = File.read(artifact_dir.join("review", "supervision-status.md"))
  feed_markdown = File.read(artifact_dir.join("review", "supervision-feed.md"))
  sidechat_markdown = File.read(artifact_dir.join("review", "supervision-sidechat.md"))
  runtime_transcript_markdown = File.read(artifact_dir.join("review", "turn-runtime-transcript.md"))
  final_response = read_json(artifact_dir.join("logs", "supervision-final.json"))
  final_status = final_response.fetch("machine_status")
  final_sidechat = final_response.dig("human_sidechat", "content").to_s
  turn_runtime_evidence = read_json(artifact_dir.join("evidence", "turn-runtime-evidence.json"))

  primary_plan_view = final_status.fetch("primary_turn_todo_plan_view", {}).to_h
  runtime_focus_hint = final_status.fetch("runtime_focus_hint", {}).to_h
  canonical_feed_entries = Array(final_status["turn_feed"].presence || final_status["activity_feed"]).select do |entry|
    entry["event_kind"].to_s.start_with?("turn_todo_")
  end
  final_status_section = status_markdown.split(/^## Poll \d+\n/).last.to_s
  dominant_fallback_markers = [
    "- Current focus: `none`",
    "- Recent progress: `none`",
    "- Active plan items: `0`",
  ].select { |marker| final_status_section.include?(marker) }

  errors = []
  unless primary_plan_view["turn_todo_plan_id"].present? && primary_plan_view["current_item_key"].present?
    errors << "supervision-final.json is missing primary_turn_todo_plan_view.current_item_key"
  end
  if dominant_fallback_markers.length >= 2
    errors << "supervision-status.md still centers fallback supervision lines: #{dominant_fallback_markers.join(', ')}"
  end
  if canonical_feed_entries.empty?
    errors << "machine_status.turn_feed does not include canonical turn_todo_* events"
  end
  sidechat_leak_tokens = (
    Acceptance::ConversationArtifacts.human_visible_leak_tokens(sidechat_markdown) +
    Acceptance::ConversationArtifacts.human_visible_leak_tokens(final_sidechat)
  ).uniq
  if sidechat_leak_tokens.any?
    errors << "supervision-sidechat still exposes raw runtime tokens: #{sidechat_leak_tokens.join(', ')}"
  end
  if runtime_focus_hint["summary"].present? && !semantic_overlap?(final_sidechat, runtime_focus_hint["summary"], minimum: 2)
    errors << "supervision-sidechat does not align with runtime_focus_hint #{runtime_focus_hint["summary"].inspect}"
  end
  if final_status["recent_progress_summary"].present? &&
      !runtime_alignment_present?(runtime_transcript_markdown, final_status["recent_progress_summary"])
    errors << "turn-runtime-transcript.md is missing a runtime-aligned recent progress narrative for #{final_status["recent_progress_summary"].inspect}"
  end
  if final_status["overall_state"] == "waiting" && runtime_focus_hint["kind"].to_s.match?(/command|process/) &&
      !semantic_overlap?(final_sidechat, runtime_focus_hint["summary"], minimum: 2)
    errors << "waiting sidechat does not mention the command/process purpose from runtime_focus_hint"
  end
  if final_status["overall_state"] == "idle"
    errors << "supervision-final.json still carries current_focus_summary for an idle snapshot" if final_status["current_focus_summary"].present?
    errors << "supervision-final.json still carries waiting_summary for an idle snapshot" if final_status["waiting_summary"].present?
    errors << "supervision-final.json still carries runtime_focus_hint for an idle snapshot" if runtime_focus_hint.present?
    errors << "supervision-sidechat does not acknowledge the idle final state" unless final_sidechat.match?(/\bidle\b/i)
    if final_sidechat.match?(/\bwaiting\b|\bblocked\b|\bworking on\b/i)
      errors << "supervision-sidechat still narrates active work for an idle final state"
    end
  end
  supervision_human_texts = [
    final_status["request_summary"],
    final_status["current_focus_summary"],
    final_status["recent_progress_summary"],
    final_status["waiting_summary"],
    final_status["blocked_summary"],
    final_status["next_step_hint"],
    primary_plan_view["goal_summary"],
    primary_plan_view.dig("current_item", "title"),
    runtime_focus_hint["summary"],
    runtime_focus_hint["current_focus_summary"],
  ]
  supervision_leak_tokens = supervision_human_texts.flat_map do |text|
    Acceptance::ConversationArtifacts.human_visible_leak_tokens(text)
  end.uniq
  if supervision_leak_tokens.any?
    errors << "supervision-final.json still exposes raw supervision tokens: #{supervision_leak_tokens.join(', ')}"
  end
  runtime_leak_tokens = Acceptance::ConversationArtifacts.human_visible_leak_tokens(runtime_transcript_markdown).uniq
  if runtime_leak_tokens.any?
    errors << "turn-runtime-transcript.md still exposes raw runtime tokens: #{runtime_leak_tokens.join(', ')}"
  end

  if primary_plan_view.present?
    current_item_key = primary_plan_view["current_item_key"].to_s
    current_item_title = primary_plan_view.dig("current_item", "title").presence || current_item_key
    goal_summary = primary_plan_view["goal_summary"].to_s

    unless status_markdown.include?(current_item_title) || status_markdown.include?(current_item_key)
      errors << "supervision-status.md is not grounded in the primary turn todo plan item #{current_item_key.inspect}"
    end
    unless runtime_transcript_markdown.include?(current_item_title) || runtime_transcript_markdown.include?(current_item_key)
      errors << "turn-runtime-transcript.md is not grounded in the primary turn todo plan item #{current_item_key.inspect}"
    end
    if goal_summary.present? && !status_markdown.include?(goal_summary)
      errors << "supervision-status.md is missing primary turn todo plan goal #{goal_summary.inspect}"
    end
  end

  canonical_feed_entries.each do |entry|
    summary = entry["summary"].to_s.strip
    next if summary.blank?

    unless feed_markdown.include?(summary)
      errors << "supervision-feed.md is missing canonical feed summary #{summary.inspect}"
    end

    timeline_correlation = Array(turn_runtime_evidence["timeline"]).any? do |event|
      runtime_alignment_present?([event["summary"], event["detail"]].compact.join(" "), summary)
    end
    unless timeline_correlation || runtime_alignment_present?(runtime_transcript_markdown, summary)
      errors << "turn-runtime-evidence.json does not correlate canonical feed summary #{summary.inspect}"
    end
  end

  return if errors.empty?

  raise <<~MSG
    2048 bundle quality contract failed:
    #{errors.map { |error| "- #{error}" }.join("\n")}
  MSG
end

def semantic_overlap?(text, reference, minimum: 2)
  return true if reference.to_s.strip.empty?

  (semantic_terms(text) & semantic_terms(reference)).length >= minimum
end

def runtime_alignment_present?(runtime_transcript_markdown, summary)
  return true if summary.to_s.strip.empty?
  return true if runtime_transcript_markdown.include?(summary)

  semantic_overlap?(runtime_transcript_markdown, summary, minimum: 2)
end

def semantic_terms(text)
  text.to_s.downcase
    .scan(/[a-z0-9]+/)
    .map { |term| term.sub(/ing\z/, "").sub(/ed\z/, "").sub(/s\z/, "") }
    .reject do |term|
      term.blank? || %w[a an and are because current for from have in into is it most of on or recent recently right the this to what while with now].include?(term)
    end
    .uniq
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
  artifact_dir:,
  workflow_run:,
  seen_live_progress_event_keys:,
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
  last_progress_signature = nil

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

    primary_plan_view = machine_status.fetch("primary_turn_todo_plan_view", {}).to_h
    latest_turn_feed_entry = Array(machine_status["turn_feed"].presence || machine_status["activity_feed"]).last || {}
    progress_signature = [
      machine_status["overall_state"],
      primary_plan_view["current_item_key"],
      primary_plan_view.dig("current_item", "status"),
      latest_turn_feed_entry["sequence"] || latest_turn_feed_entry["summary"],
      machine_status["current_focus_summary"],
      machine_status["recent_progress_summary"],
      Array(machine_status["active_subagent_turn_todo_plan_views"]).map do |entry|
        [entry["subagent_session_id"], entry["current_item_key"], entry.dig("current_item", "status")]
      end,
    ]
    if progress_signature != last_progress_signature
      log_capstone_phase(
        artifact_dir: artifact_dir,
        phase: "supervision_progress",
        details: {
          "poll_index" => polls.length,
          "overall_state" => machine_status["overall_state"],
          "current_focus_summary" => machine_status["current_focus_summary"],
          "recent_progress_summary" => machine_status["recent_progress_summary"],
          "primary_turn_todo_plan_current_item_key" => primary_plan_view["current_item_key"],
          "primary_turn_todo_plan_current_item_title" => primary_plan_view.dig("current_item", "title"),
          "latest_turn_feed_event_kind" => latest_turn_feed_entry["event_kind"],
          "latest_turn_feed_summary" => latest_turn_feed_entry["summary"],
          "active_subagent_count" => Array(machine_status["active_subagent_turn_todo_plan_views"]).presence&.length || Array(machine_status["active_subagents"]).length,
        }
      )
      last_progress_signature = progress_signature
    end

    Acceptance::LiveProgressFeed.capture!(
      artifact_dir: artifact_dir,
      workflow_run: workflow_run.reload,
      owner_conversation: workflow_run.conversation,
      seen_event_keys: seen_live_progress_event_keys
    )

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
    "human_visible_leak_tokens" => Acceptance::ConversationArtifacts.human_visible_leak_tokens(human_sidechat.fetch("content")),
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

  write_json(artifact_dir.join("evidence", "control-intent-matrix.json"), payload)
  payload
end

def build_conversation_runtime_validation(tool_invocations:)
  ManualAcceptance::ConversationRuntimeValidation.build(tool_invocations:)
end

def build_rescue_history_entry(attempt_no:, workflow_run:, runtime_validation:, host_validation:, playwright_validation:, host_playability_skip_reason:, repair_prompt:)
  reasons = []
  reasons << "workflow_not_completed" unless workflow_run.lifecycle_state == "completed"
  reasons << "runtime_validation_failed" unless Acceptance::HostValidation.runtime_validation_passed?(runtime_validation)
  reasons << "host_validation_failed" unless Acceptance::HostValidation.host_validation_passed?(host_validation:, playwright_validation:)
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
    lines << Acceptance::HostValidation.command_result_excerpt(host_validation.fetch("npm_install"), limit:)
  end
  if host_validation.dig("npm_test", "success") == false
    lines << "- host `npm test` failed:"
    lines << Acceptance::HostValidation.command_result_excerpt(host_validation.fetch("npm_test"), limit:)
  end
  if host_validation.dig("npm_build", "success") == false
    lines << "- host `npm run build` failed:"
    lines << Acceptance::HostValidation.command_result_excerpt(host_validation.fetch("npm_build"), limit:)
  end
  if host_validation.dig("preview_http", "status") != 200
    lines << "- host static preview was not reachable at `http://127.0.0.1:4174/`."
  end
  if Acceptance::HostValidation.playwright_result_available?(playwright_validation) &&
      !Acceptance::HostValidation.playwright_verification_passed?(playwright_validation)
    lines << "- host browser verification ran but its assertions failed:"
    lines << Acceptance::HostValidation.command_result_excerpt(playwright_validation.fetch("test"), limit:)
    lines.concat(Acceptance::HostValidation.playability_failure_observations(playwright_validation:))
  elsif !Acceptance::HostValidation.playwright_result_available?(playwright_validation) && host_playability_skip_reason.present?
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
  if playwright_validation.dig("result", "gameOverReached") == false
    lines << "- if the board reaches a terminal no-moves state, the visible status must contain the exact words `Game over`"
  end
  lines << "- finish with a concise completion note that reflects what actually passed"

  lines.join("\n")
end

case capstone_phase
when "bootstrap"
  FileUtils.rm_rf(artifact_dir)
  FileUtils.mkdir_p(artifact_dir)
  FileUtils.rm_rf(generated_app_dir)

  unless ActiveModel::Type::Boolean.new.cast(ENV["CAPSTONE_SKIP_BACKEND_RESET"])
    ManualAcceptanceSupport.reset_backend_state!
  end
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

write_json(artifact_dir.join("evidence", "acceptance-registration.json"), {
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
write_json(artifact_dir.join("evidence", "capstone-run-bootstrap.json"), {
  "scenario_date" => scenario_date,
  "operator" => OPERATOR_NAME,
  "selector" => selector,
  "attempt_count" => 0,
  "workspace_root" => workspace_root.to_s,
  "generated_app_dir" => generated_app_dir.to_s,
  "skill_source_manifest_path" => skill_sources.fetch("manifest_path"),
  "prompt" => prompt,
})
write_json(artifact_dir.join("evidence", "skills-validation.json"), skills_validation)
write_json(artifact_dir.join("evidence", "attempt-history.json"), [])
write_json(artifact_dir.join("evidence", "rescue-history.json"), [])

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
seen_live_progress_event_keys = Set.new

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
    artifact_dir: artifact_dir,
    workflow_run: run.fetch(:workflow_run),
    seen_live_progress_event_keys: seen_live_progress_event_keys,
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
      "primary_turn_todo_plan_current_item_key" => supervision_trace.dig("final_response", "machine_status", "primary_turn_todo_plan_view", "current_item_key"),
      "primary_turn_todo_plan_current_item_title" => supervision_trace.dig("final_response", "machine_status", "primary_turn_todo_plan_view", "current_item", "title"),
      "latest_turn_feed_summary" => Array(supervision_trace.dig("final_response", "machine_status", "turn_feed")).last&.fetch("summary", nil),
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
  host_validation_bundle = Acceptance::HostValidation.run!(
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
      "playwright_verification_passed" => Acceptance::HostValidation.playwright_verification_passed?(playwright_validation),
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
      "playwright_verification_passed" => Acceptance::HostValidation.playwright_verification_passed?(playwright_validation),
    },
  }
  write_json(artifact_dir.join("evidence", "attempt-history.json"), attempt_history)
  Acceptance::ConversationArtifacts.write_supervision_artifacts!(
    artifact_dir: artifact_dir,
    supervision_trace: supervision_trace,
    prompt: SUPERVISION_PROMPT
  )

  if workflow_run.lifecycle_state == "completed" &&
      Acceptance::HostValidation.runtime_validation_passed?(runtime_validation) &&
      Acceptance::HostValidation.host_validation_passed?(host_validation:, playwright_validation:)
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
    write_text(artifact_dir.join("evidence", "terminal-failure.txt"), terminal_failure_message)
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
  write_json(artifact_dir.join("evidence", "rescue-history.json"), rescue_history)
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

conversation_artifacts = Acceptance::ConversationArtifacts.capture_export_roundtrip!(
  artifact_dir: artifact_dir,
  conversation: conversation,
  machine_credential: machine_credential,
  supervision_trace: supervision_trace,
  prompt: SUPERVISION_PROMPT
)

source_transcript = conversation_artifacts.fetch("source_transcript")
source_diagnostics_show = conversation_artifacts.fetch("source_diagnostics_show")
source_diagnostics_turns = conversation_artifacts.fetch("source_diagnostics_turns")
user_bundle_path = conversation_artifacts.fetch("user_bundle_path")
debug_bundle_path = conversation_artifacts.fetch("debug_bundle_path")
export_result = conversation_artifacts.fetch("export_result")
debug_export_result = conversation_artifacts.fetch("debug_export_result")
import_result = conversation_artifacts.fetch("import_result")
imported_conversation_id = conversation_artifacts.fetch("imported_conversation_id")
imported_transcript = conversation_artifacts.fetch("imported_transcript")
imported_diagnostics_show = conversation_artifacts.fetch("imported_diagnostics_show")
source_items = conversation_artifacts.fetch("source_items")
imported_items = conversation_artifacts.fetch("imported_items")
transcript_roundtrip_match = conversation_artifacts.fetch("transcript_roundtrip_match")
parsed_debug = conversation_artifacts.fetch("parsed_debug")

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

write_json(artifact_dir.join("evidence", "capstone-run-bootstrap.json"), {
  "scenario_date" => scenario_date,
  "operator" => OPERATOR_NAME,
  "selector" => selector,
  "attempt_count" => attempt_history.length,
  "workspace_root" => workspace_root.to_s,
  "generated_app_dir" => generated_app_dir.to_s,
  "skill_source_manifest_path" => skill_sources.fetch("manifest_path"),
  "prompt" => prompt,
})
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

subagent_runtime_snapshots = Acceptance::ConversationArtifacts.capture_subagent_runtime_snapshots!(
  artifact_dir: artifact_dir,
  subagent_sessions: subagent_sessions,
  machine_credential: machine_credential
)

main_diagnostics_turn = source_diagnostics_turns.fetch("items").fetch(0)
turn_runtime_report = Acceptance::TurnRuntimeTranscript.build(
  conversation_id: conversation.public_id,
  turn_id: turn.public_id,
  phase_events: artifact_dir.join("logs", "phase-events.jsonl").exist? ? File.readlines(artifact_dir.join("logs", "phase-events.jsonl"), chomp: true).filter_map { |line| JSON.parse(line) if line.present? } : [],
  workflow_node_events: workflow_node_events,
  usage_events: usage_events,
  tool_invocations: tool_invocations,
  command_runs: command_runs,
  process_runs: process_runs,
  subagent_sessions: subagent_sessions,
  subagent_runtime_snapshots: subagent_runtime_snapshots,
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
Acceptance::ReviewArtifacts.write_turns!(
  path: artifact_dir.join("review", "turns.md"),
  scenario_date: scenario_date,
  operator_name: OPERATOR_NAME,
  runtime_mode: RUNTIME_MODE,
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
    "review/conversation-transcript.md",
    "review/turn-runtime-transcript.md",
    "review/supervision-sidechat.md",
    "review/supervision-status.md",
    "review/supervision-feed.md",
    "review/workspace-validation.md",
    "review/playability-verification.md",
    "review/export-roundtrip.md",
    "review/capability-activation.md",
    "review/failure-classification.md",
    "evidence/run-summary.json",
    "evidence/agent-evaluation.json",
    "evidence/capability-activation.json",
    "evidence/failure-classification.json",
    "evidence/turn-runtime-evidence.json",
    "evidence/subagent-runtime-snapshots.json",
    "evidence/attempt-history.json",
    "evidence/rescue-history.json",
    "evidence/skills-validation.json",
    "logs/phase-events.jsonl",
    "logs/live-progress-events.jsonl",
    "logs/supervision-session.json",
    "logs/supervision-polls.json",
    "logs/supervision-final.json",
    ("evidence/terminal-failure.txt" if terminal_failure_message.present?),
    ("evidence/control-intent-matrix.json" if control_intent_matrix.present?),
    ("playable/host-preview.json" if preview_http.present?),
    ("playable/host-playwright-verification.json" if Acceptance::HostValidation.playwright_result_available?(playwright_validation)),
    ("playable/host-playability.png" if Acceptance::HostValidation.playwright_result_available?(playwright_validation)),
  ].compact
)
Acceptance::ReviewArtifacts.write_collaboration_notes!(
  path: artifact_dir.join("review", "collaboration-notes.md"),
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
Acceptance::ReviewArtifacts.write_runtime_and_bindings!(
  path: artifact_dir.join("review", "runtime-and-bindings.md"),
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
Acceptance::ReviewArtifacts.write_workspace_artifacts!(
  path: artifact_dir.join("review", "workspace-artifacts.md"),
  workspace_root: workspace_root,
  generated_app_dir: generated_app_dir,
  host_validation_notes: host_validation_notes,
  preview_port: preview_port
)
Acceptance::HostValidation.write_playability_verification!(
  path: artifact_dir.join("review", "playability-verification.md"),
  playability_result: playwright_validation["result"],
  playwright_test: playwright_validation["test"],
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
    "workspace_validation" => artifact_dir.join("review", "workspace-validation.md"),
    "skills_validation" => artifact_dir.join("evidence", "skills-validation.json"),
    "supervision_session" => artifact_dir.join("logs", "supervision-session.json"),
    "supervision_polls" => artifact_dir.join("logs", "supervision-polls.json"),
    "supervision_final" => artifact_dir.join("logs", "supervision-final.json"),
    "supervision_status" => artifact_dir.join("review", "supervision-status.md"),
    "conversation_export" => user_bundle_path,
    "conversation_debug_export" => debug_bundle_path,
    "transcript_roundtrip" => artifact_dir.join("exports", "transcript-roundtrip-compare.json"),
    "host_npm_install" => artifact_dir.join("playable", "host-npm-install.json"),
    "host_npm_test" => artifact_dir.join("playable", "host-npm-test.json"),
    "host_npm_build" => artifact_dir.join("playable", "host-npm-build.json"),
    "host_preview" => artifact_dir.join("playable", "host-preview.json"),
    "host_playwright_verification" => artifact_dir.join("playable", "host-playwright-verification.json"),
    "host_playability_image" => artifact_dir.join("playable", "host-playability.png"),
    "playability_verification" => artifact_dir.join("review", "playability-verification.md"),
  },
  workspace_paths: {
    "generated_app_dir" => generated_app_dir,
  },
  skill_validation: skills_validation,
  transcript_roundtrip_match: transcript_roundtrip_match,
  supervision_trace: supervision_trace
)
write_json(artifact_dir.join("evidence", "capability-activation.json"), capability_report)
write_text(
  artifact_dir.join("review", "capability-activation.md"),
  Acceptance::BenchmarkReporting.capability_activation_markdown(
    capability_report: capability_report
  )
)

workload_outcome = Acceptance::BenchmarkReporting.determine_workload_outcome(
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
      "playwright_verification_passed" => Acceptance::HostValidation.playwright_verification_passed?(playwright_validation),
    },
  },
  rescue_history: rescue_history,
  timeline: Acceptance::BenchmarkReporting.build_failure_timeline(
    attempt_history: attempt_history,
    terminal_failure_message: terminal_failure_message
  ),
  notes: [terminal_failure_message].compact
)
write_json(artifact_dir.join("evidence", "failure-classification.json"), failure_report)
write_text(
  artifact_dir.join("review", "failure-classification.md"),
  Acceptance::BenchmarkReporting.failure_classification_markdown(
    failure_report: failure_report
  )
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
  "subagent_runtime_snapshot_count" => subagent_runtime_snapshots.length,
  "skills_validation_path" => artifact_dir.join("evidence", "skills-validation.json").to_s,
  "capability_activation_path" => artifact_dir.join("evidence", "capability-activation.json").to_s,
  "failure_classification_path" => artifact_dir.join("evidence", "failure-classification.json").to_s,
  "phase_events_path" => artifact_dir.join("logs", "phase-events.jsonl").to_s,
  "live_progress_events_path" => artifact_dir.join("logs", "live-progress-events.jsonl").to_s,
  "review_index_path" => artifact_dir.join("review", "index.md").to_s,
  "review_turn_runtime_transcript_path" => artifact_dir.join("review", "turn-runtime-transcript.md").to_s,
  "evidence_manifest_path" => artifact_dir.join("evidence", "artifact-manifest.json").to_s,
  "evidence_run_summary_path" => artifact_dir.join("evidence", "run-summary.json").to_s,
  "evidence_turn_runtime_path" => artifact_dir.join("evidence", "turn-runtime-evidence.json").to_s,
  "subagent_runtime_snapshots_path" => artifact_dir.join("evidence", "subagent-runtime-snapshots.json").to_s,
  "host_playability_artifact" => (artifact_dir.join("playable", "host-playwright-verification.json").to_s if Acceptance::HostValidation.playwright_result_available?(playwright_validation)),
  "control_intent_matrix_path" => (artifact_dir.join("evidence", "control-intent-matrix.json").to_s if control_intent_matrix.present?),
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
    "playwright_verification_passed" => Acceptance::HostValidation.playwright_verification_passed?(playwright_validation),
  },
}
summary["control_intent_matrix"] = control_intent_matrix.fetch("summary") if control_intent_matrix.present?

evaluation = Acceptance::BenchmarkReporting.build_agent_evaluation(
  summary: summary,
  diagnostics_turn: main_diagnostics_turn
)
summary["agent_evaluation"] = evaluation.transform_values { |payload| payload.fetch("rating") }

write_text(
  artifact_dir.join("review", "agent-evaluation.md"),
  Acceptance::BenchmarkReporting.agent_evaluation_markdown(evaluation)
)
write_json(artifact_dir.join("evidence", "agent-evaluation.json"), evaluation)
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
Acceptance::ArtifactBundle.write_review_index!(
  path: artifact_dir.join("review", "index.md"),
  summary: summary
)
Acceptance::ArtifactBundle.write_manifest!(
  path: artifact_dir.join("evidence", "artifact-manifest.json"),
  artifact_stamp: artifact_stamp,
  summary: summary
)
Acceptance::ArtifactBundle.write_root_readme!(
  path: artifact_dir.join("README.md"),
  artifact_stamp: artifact_stamp,
  summary: summary
)
assert_2048_bundle_quality_contract!(artifact_dir:)

puts JSON.pretty_generate(summary)
raise terminal_failure_message if terminal_failure_message.present?
