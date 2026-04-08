require "test_helper"
require "tmpdir"

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
    refute_includes scenario, '{ "key" => "skills", "required" => false }'
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

  test "acceptance scenario uses shared capstone roundtrip helper and avoids staged skill dependencies" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    boot = Rails.root.join("../acceptance/lib/boot.rb").read
    helper = Rails.root.join("../acceptance/lib/capstone_app_api_roundtrip.rb")

    assert helper.exist?, "expected shared capstone roundtrip helper to exist"
    assert_includes boot, "require_relative 'capstone_app_api_roundtrip'"
    assert_includes scenario, "Acceptance::CapstoneAppApiRoundtrip"
    refute_includes scenario, "Use `$using-superpowers`."
    refute_includes scenario, "`$find-skills` is installed and available"
    refute_includes scenario, "prepare_skill_sources!"
    refute_includes scenario, "install_and_validate_skills!"
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

    refute_includes scenario, 'write_json(artifact_dir.join("evidence", "skills-validation.json"), skills_validation)'
    refute_includes scenario, '"skill_source_manifest_path"'
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

  test "acceptance scenario uses executor bootstrap and registration identifiers" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    helper = Rails.root.join("../acceptance/lib/capstone_app_api_roundtrip.rb").read

    assert_includes scenario, '"executor_machine_credential"'
    assert_includes scenario, '"executor_program_id"'
    assert_includes helper, "'executor_program_display_name'"
    assert_includes scenario, '"executor_session_id"'
    assert_includes helper, "'executor_fingerprint'"
    assert_includes scenario, "ExecutorProgram.find_by_public_id!"
    assert_includes scenario, "ExecutorSession.find_by_public_id!"
  end

  test "acceptance registration artifact redacts machine credentials with a non-reversible fingerprint" do
    require Rails.root.join("../acceptance/lib/credential_redaction")
    require Rails.root.join("../acceptance/lib/capstone_app_api_roundtrip")

    artifact = Acceptance::CapstoneAppApiRoundtrip.registration_artifact(
      agent_program: Struct.new(:public_id, :display_name).new("agent_123", "Fenix"),
      agent_program_version: Struct.new(:public_id, :fingerprint).new("agent_version_123", "program-fingerprint"),
      executor_program: Struct.new(:public_id, :display_name, :executor_fingerprint).new("executor_123", "Executor", "executor-fingerprint"),
      machine_credential: "0123456789abcdef"
    )

    assert_equal "sha256:9f9f5111f7b2:REDACTED", artifact.fetch("machine_credential_redacted")
    refute_equal "0123456789abcdef", artifact.fetch("machine_credential_redacted")
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

  test "dedicated skills validation stays separate from the capstone and uses scoped home roots" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_skills_validation.rb").read
    capstone = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    fresh_start = Rails.root.join("../acceptance/bin/fresh_start_stack.sh").read
    docker_activate = Rails.root.join("../acceptance/bin/activate_fenix_docker_runtime.sh").read

    refute_includes capstone, "skills_install"
    assert_includes scenario, "ENV.fetch('FENIX_HOME_ROOT'"
    refute_includes scenario, "FENIX_LIVE_SKILLS_ROOT"
    refute_includes scenario, "FENIX_STAGING_SKILLS_ROOT"
    refute_includes scenario, "FENIX_BACKUP_SKILLS_ROOT"
    assert_includes fresh_start, "FENIX_HOME_ROOT"
    assert_includes docker_activate, "FENIX_HOME_ROOT"
  end

  test "skills validation scenario proves same-program sharing and different-program isolation" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_skills_validation.rb").read

    assert_includes scenario, "ensure_disposable_fenix_home_root!"
    assert_includes scenario, "basename must start with acceptance-fenix-home"
    assert_includes scenario, "ENV['FENIX_HOME_ROOT'] = fenix_home_root.to_s"
    assert_includes scenario, "'conversation_a'"
    assert_includes scenario, "'conversation_b'"
    assert_includes scenario, "'conversation_c'"
    assert_includes scenario, "mode: 'skills_install'"
    assert_includes scenario, "mode: 'skills_load'"
    assert_includes scenario, "mode: 'skills_read_file'"
    assert_includes scenario, "'shared_conversation_success'"
    assert_includes scenario, "'different_program_failure'"
    assert_includes scenario, "'install_scope_root'"
    assert_includes scenario, "'workflow_lifecycle_state' => 'failed'"
    assert_includes scenario, "'agent_task_run_state' => 'failed'"
  end

  test "skills validation docs stay aligned with the active acceptance runtime port" do
    readme = Rails.root.join("../agents/fenix/README.md").read

    assert_includes readme, "`AGENT_FENIX_PORT=3101 bin/dev`"
    refute_includes readme, "AGENT_FENIX_PORT=3102"
    refute_includes readme, "dedicated `3102` runtime"
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

  test "acceptance scenario sends the executor credential to runtime bindings review output only" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read
    write_turns_call = scenario[/Acceptance::ReviewArtifacts\.write_turns!\([\s\S]*?\n\)\nAcceptance::ReviewArtifacts\.write_collaboration_notes!/m]
    runtime_bindings_call = scenario[/Acceptance::ReviewArtifacts\.write_runtime_and_bindings!\([\s\S]*?\n\)\nAcceptance::ReviewArtifacts\.write_workspace_artifacts!/m]

    assert_includes runtime_bindings_call, "executor_machine_credential: executor_machine_credential"
    refute_includes write_turns_call, "executor_machine_credential: executor_machine_credential"
  end

  test "review artifacts drop staged skill-source bookkeeping" do
    helper = Rails.root.join("../acceptance/lib/review_artifacts.rb").read

    refute_includes helper, "skill_source_manifest_path:"
    refute_includes helper, "Skill source manifest"
    refute_includes helper, "staged GitHub skill sources"
  end

  test "runtime bindings review artifact preserves distinct agent and executor credentials" do
    require Rails.root.join("../acceptance/lib/credential_redaction")
    require Rails.root.join("../acceptance/lib/review_artifacts")

    Dir.mktmpdir do |dir|
      artifact_path = Pathname.new(dir).join("runtime-and-bindings.md")

      Acceptance::ReviewArtifacts.write_runtime_and_bindings!(
        path: artifact_path,
        workspace_root: Pathname.new("/tmp/fenix-workspace"),
        machine_credential: "0123456789abcdef",
        executor_machine_credential: "fedcba9876543210",
        agent_program: Struct.new(:public_id).new("agent_123"),
        agent_program_version: Struct.new(:public_id).new("agent_version_123"),
        executor_program: Struct.new(:public_id).new("executor_123"),
        docker_container: "fenix-capstone",
        runtime_base_url: "http://127.0.0.1:3101",
        runtime_worker_boot: nil
      )

      artifact = artifact_path.read

      assert_includes artifact, "FENIX_MACHINE_CREDENTIAL=sha256:9f9f5111f7b2:REDACTED"
      assert_includes artifact, "FENIX_EXECUTION_MACHINE_CREDENTIAL=sha256:3465f6e6975b:REDACTED"
      refute_includes artifact, "0123456789abcdef"
      refute_includes artifact, "fedcba9876543210"
    end
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

  test "manual acceptance support derives bundled runtime identity from the live manifest" do
    helper = Rails.root.join("../core_matrix/script/manual/manual_acceptance_support.rb").read
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes helper, 'agent_key: manifest.fetch("agent_key")'
    assert_includes helper, 'display_name: manifest.fetch("display_name")'
    assert_includes helper, 'sdk_version: manifest.fetch("sdk_version")'
    refute_includes helper, 'agent_key: "fenix"'
    refute_includes helper, 'display_name: "Bundled Fenix"'
    refute_includes scenario, 'sdk_version: "fenix-0.1.0"'
  end

  test "manual acceptance support still allows explicit sdk version override for rotation validations" do
    helper = Rails.root.join("../core_matrix/script/manual/manual_acceptance_support.rb").read
    rotation = Rails.root.join("../acceptance/scenarios/bundled_rotation_validation.rb").read

    assert_includes helper, 'resolved_sdk_version = sdk_version || manifest.fetch("sdk_version")'
    assert_includes helper, "sdk_version: resolved_sdk_version"
    assert_includes rotation, 'sdk_version: "fenix-0.2.0"'
    assert_includes rotation, 'sdk_version: "fenix-0.0.9"'
  end

  test "acceptance docs no longer prescribe staged workflow skills for the fenix capstone" do
    readme = Rails.root.join("../acceptance/README.md").read
    checklist = Rails.root.join("../docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md").read

    assert_includes readme, "bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh"
    refute_includes checklist, "using-superpowers"
    refute_includes checklist, "find-skills"
    refute_includes checklist, "GitHub-sourced skills"
  end

  test "acceptance scenario makes the game-over status contract explicit" do
    prompt_helper = Rails.root.join("../acceptance/lib/capstone_app_api_roundtrip.rb").read
    helper = Rails.root.join("../acceptance/lib/host_validation.rb").read

    assert_includes prompt_helper,
      "- expose a game-over status through `data-testid=\"status\"` that visibly contains the words `Game over` when no moves remain"
    assert_includes prompt_helper,
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
