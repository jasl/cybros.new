require "test_helper"

class FenixCapstoneAcceptanceContractTest < ActiveSupport::TestCase
  test "host playability script treats hyphenated game-over status as terminal" do
    script = Rails.root.join("../acceptance/lib/host_validation.rb").read

    assert_includes script, "gameOverStatusPattern = /game(?:\\\\s|-)?over/i",
      "expected host playability verification to accept both 'game over' and 'game-over' status text"
  end

  test "acceptance scenario supports supervision control phrase-matrix validation" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'ENV["CAPSTONE_ENABLE_CONTROL_ACCEPTANCE"]'
    assert_includes scenario, "ConversationControlPhraseMatrix.load!"
    assert_includes scenario, 'artifact_dir.join("evidence", "control-intent-matrix.json")'
  end

  test "acceptance fixture and loader define positive negative and ambiguous control utterances" do
    fixture = Rails.root.join("../acceptance/fixtures/conversation_control_phrase_matrix.yml")
    loader = Rails.root.join("../acceptance/lib/conversation_control_phrase_matrix.rb")

    assert fixture.exist?, "expected control phrase matrix fixture to exist"
    assert loader.exist?, "expected control phrase matrix loader to exist"

    fixture_body = fixture.read
    loader_body = loader.read

    assert_includes fixture_body, "positive:"
    assert_includes fixture_body, "negative:"
    assert_includes fixture_body, "ambiguous:"
    assert_includes loader_body, "YAML.load_file"
  end

  test "acceptance scenario threads runtime validation into playability artifacts" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/host_validation.rb").read

    assert_includes scenario, "Acceptance::HostValidation.run!("
    assert_includes helper,
      "def run!(generated_app_dir:, artifact_dir:, preview_port:, runtime_validation:, persist_artifacts: true)"
    refute_includes helper, "runtime_validation: nil"
  end

  test "acceptance scenario enables detailed supervision progress for sidechat validation" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "policy.detailed_progress_enabled = true"
  end

  test "acceptance scenario writes capability activation benchmark output" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'artifact_dir.join("evidence", "capability-activation.json")'
    assert_includes scenario, 'artifact_dir.join("review", "capability-activation.md")'
  end

  test "acceptance scenario writes failure classification benchmark output" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'artifact_dir.join("evidence", "failure-classification.json")'
    assert_includes scenario, 'artifact_dir.join("review", "failure-classification.md")'
  end

  test "acceptance scenario uses shared capability benchmark helpers" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "Acceptance::CapabilityActivation"
    assert_includes scenario, "Acceptance::FailureClassification"
  end

  test "acceptance scenario maps staged skill sources into the docker workspace mount" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "def runtime_visible_workspace_path"
    assert_includes scenario, 'ENV.fetch("FENIX_DOCKER_MOUNT_WORKSPACE_ROOT", "/workspace")'
    assert_includes scenario, '"runtime_source_path"'
  end

  test "shell-driven capstone skips redundant backend reset during bootstrap" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    shell_script = Rails.root.join("../acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh").read

    assert_includes scenario, 'ENV["CAPSTONE_SKIP_BACKEND_RESET"]'
    assert_includes shell_script, "CAPSTONE_SKIP_BACKEND_RESET=true"
  end

  test "clean benchmark runs do not emit false failure categories" do
    helper = Rails.root.join("../acceptance/lib/benchmark_reporting.rb").read

    assert_includes helper, "next if workflow_completed && host_failed_keys.empty? && runtime_failed_keys.empty?"
    assert_includes helper, "stringify_keys(validation_hash).select { |_key, value| value == false }.keys"
  end

  test "acceptance scenario checkpoints benchmark artifacts before the final export phase" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'write_json(artifact_dir.join("evidence", "skills-validation.json"), skills_validation)'
    assert_includes scenario, 'write_json(artifact_dir.join("evidence", "attempt-history.json"), attempt_history)'
    assert_includes scenario, 'write_json(artifact_dir.join("evidence", "rescue-history.json"), rescue_history)'
    assert_includes scenario, 'write_text(artifact_dir.join("evidence", "terminal-failure.txt"), terminal_failure_message)'
  end

  test "acceptance scenario emits phase progress events during long benchmark runs" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "def log_capstone_phase"
    assert_includes scenario, 'artifact_dir.join("logs", "phase-events.jsonl")'
    assert_includes scenario, 'phase: "supervision_progress"'
    assert_includes scenario, 'phase: "host_validation_started"'
    assert_includes scenario, 'phase: "benchmark_reporting_complete"'
  end

  test "acceptance scenario writes turn runtime transcript artifacts and review indexes" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "Acceptance::TurnRuntimeTranscript"
    assert_includes scenario, 'artifact_dir.join("review", "turn-runtime-transcript.md")'
    assert_includes scenario, 'artifact_dir.join("evidence", "turn-runtime-evidence.json")'
    assert_includes scenario, 'artifact_dir.join("logs", "turn-runtime-events.jsonl")'
    assert_includes scenario, "Acceptance::ArtifactBundle.write_review_index!"
  end

  test "acceptance gate requires plan-first supervision replay bundles and runtime evidence" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/conversation_artifacts.rb").read

    assert_includes scenario, 'artifact_dir.join("review", "supervision-sidechat.md")'
    assert_includes scenario, 'artifact_dir.join("review", "supervision-eval-bundle.json")'
    assert_includes scenario, "Acceptance::ConversationArtifacts.human_visible_leak_tokens"
    assert_includes scenario, "semantic_overlap?"
    assert_includes scenario, 'runtime_evidence = final_status.fetch("runtime_evidence", {}).to_h'
    assert_includes scenario, "primary_plan_view.present?"
    assert_includes scenario, 'review", "supervision-eval-bundle.json"'
    assert_includes scenario, 'primary_plan_view["goal_summary"]'
    assert_includes scenario, 'primary_plan_view.dig("current_item", "title")'
    assert_includes scenario, 'final_status["recent_progress_summary"]'
    assert_includes scenario, 'final_status["waiting_summary"]'
    assert_includes scenario, 'final_status["blocked_summary"]'
    assert_includes scenario, "runtime evidence"
    assert_includes scenario, "turn-runtime-transcript.md still exposes raw runtime tokens"
    assert_includes helper, "Runtime evidence"
    assert_includes helper, "def supervision_eval_bundle"
    assert_includes helper, "workspace_[a-z0-9_]+"
  end

  test "acceptance scenario copies host playwright setup outputs into playable artifacts" do
    helper = Rails.root.join("../acceptance/lib/host_validation.rb").read
    artifact_bundle = Rails.root.join("../acceptance/lib/artifact_bundle.rb").read

    assert_includes helper, '"host-playwright-install.json"'
    assert_includes helper, '"host-playwright-test.json"'
    assert_includes artifact_bundle, "[Playable Outputs](../playable/)"
  end

  test "acceptance scenario uses shared artifact bundle helper" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "Acceptance::ArtifactBundle"
    assert_includes scenario, "Acceptance::ArtifactBundle.write_manifest!"
    assert_includes scenario, "Acceptance::ArtifactBundle.write_review_index!"
    assert_includes scenario, "Acceptance::ArtifactBundle.write_root_readme!"
    assert_includes scenario, 'artifact_dir.join("evidence", "artifact-manifest.json")'
  end

  test "acceptance scenario uses shared conversation artifacts helper" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/conversation_artifacts.rb")

    assert helper.exist?, "expected shared conversation artifacts helper to exist"
    assert_includes scenario, "Acceptance::ConversationArtifacts.capture_export_roundtrip!"
    assert_includes scenario, "Acceptance::ConversationArtifacts.write_supervision_artifacts!"
    assert_includes scenario, "Acceptance::ConversationArtifacts.capture_subagent_runtime_snapshots!"
  end

  test "acceptance scenario uses shared review artifacts helper" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/review_artifacts.rb")

    assert helper.exist?, "expected shared review artifacts helper to exist"
    assert_includes scenario, "Acceptance::ReviewArtifacts.write_turns!"
    assert_includes scenario, "Acceptance::ReviewArtifacts.write_collaboration_notes!"
    assert_includes scenario, "Acceptance::ReviewArtifacts.write_runtime_and_bindings!"
    assert_includes scenario, "Acceptance::ReviewArtifacts.write_workspace_artifacts!"
  end

  test "acceptance scenario uses shared host validation helper" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/host_validation.rb").read

    assert_includes scenario, "Acceptance::HostValidation.run!"
    assert_includes scenario, "Acceptance::HostValidation.playability_failure_observations"
    assert_includes scenario, "Acceptance::HostValidation.write_playability_verification!"
    assert_includes scenario, 'playwright_test: playwright_validation["test"]'
    assert_includes scenario, "Acceptance::HostValidation.runtime_validation_passed?"
    assert_includes scenario, "Acceptance::HostValidation.host_validation_passed?"
    assert_includes scenario, "Acceptance::HostValidation.command_result_excerpt"
    assert_includes helper, "def write_playability_verification!"
  end

  test "acceptance scenario makes the game-over status contract explicit" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/host_validation.rb").read

    assert_includes scenario,
      "- expose a game-over status through `data-testid=\"status\"` that visibly contains the words `Game over` when no moves remain"
    assert_includes scenario,
      "- if the board reaches a terminal no-moves state, the visible status must contain the exact words `Game over`"
    assert_includes helper, "def playability_failure_observations(playwright_validation:)"
  end

  test "acceptance scenario uses shared benchmark reporting helper" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/benchmark_reporting.rb")

    assert helper.exist?, "expected shared benchmark reporting helper to exist"
    assert_includes scenario, "Acceptance::BenchmarkReporting"
    assert_includes scenario, "Acceptance::BenchmarkReporting.determine_workload_outcome"
    assert_includes scenario, "Acceptance::BenchmarkReporting.build_failure_timeline"
    assert_includes scenario, "Acceptance::BenchmarkReporting.build_agent_evaluation"
    assert_includes scenario, "Acceptance::BenchmarkReporting.capability_activation_markdown"
    assert_includes scenario, "Acceptance::BenchmarkReporting.failure_classification_markdown"
    assert_includes scenario, "Acceptance::BenchmarkReporting.agent_evaluation_markdown"
  end

  test "acceptance scenario uses shared live progress feed helper" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/live_progress_feed.rb")

    assert helper.exist?, "expected shared live progress helper to exist"
    assert_includes scenario, "Acceptance::LiveProgressFeed.capture!"
    assert_includes scenario, 'artifact_dir.join("logs", "live-progress-events.jsonl")'
  end

  test "behavior docs point to supervision and control instead of observation as the living source of truth" do
    redirect_doc = Rails.root.join("docs/behavior/conversation-observation-and-supervisor-status.md")
    supervision_doc = Rails.root.join("docs/behavior/conversation-supervision-and-control.md")
    progress_doc = Rails.root.join("docs/behavior/agent-progress-and-plan-items.md")

    assert supervision_doc.exist?, "expected supervision behavior doc to exist"
    assert progress_doc.exist?, "expected progress behavior doc to exist"

    redirect_body = redirect_doc.read

    assert_includes redirect_body, "migration note"
    assert_includes redirect_body, "conversation-supervision-and-control.md"
  end
end
