require "test_helper"

class FenixCapstoneAcceptanceContractTest < ActiveSupport::TestCase
  test "host playability script treats hyphenated game-over status as terminal" do
    script = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes script, "/game(?:\\s|-)?over/i",
      "expected host playability verification to accept both 'game over' and 'game-over' status text"
  end

  test "acceptance scenario supports supervision control phrase-matrix validation" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'ENV["CAPSTONE_ENABLE_CONTROL_ACCEPTANCE"]'
    assert_includes scenario, "ConversationControlPhraseMatrix.load!"
    assert_includes scenario, 'artifact_dir.join("control-intent-matrix.json")'
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

    assert_includes scenario,
      "def evaluate_workspace_validation(generated_app_dir:, artifact_dir:, preview_port:, runtime_validation:, persist_artifacts: true)"
    refute_includes scenario, "runtime_validation: nil"
  end

  test "acceptance scenario enables detailed supervision progress for sidechat validation" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "policy.detailed_progress_enabled = true"
  end

  test "acceptance scenario writes capability activation benchmark output" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'artifact_dir.join("capability-activation.json")'
  end

  test "acceptance scenario writes failure classification benchmark output" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'artifact_dir.join("failure-classification.json")'
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

  test "clean benchmark runs do not emit false failure categories" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "next if workflow_completed && !host_failed && !runtime_failed"
    assert_includes scenario, "runtime_validation.select { |_key, value| value == false }.keys"
  end

  test "acceptance scenario checkpoints benchmark artifacts before the final export phase" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, 'write_json(artifact_dir.join("skills-validation.json"), skills_validation)'
    assert_includes scenario, 'write_json(artifact_dir.join("attempt-history.json"), attempt_history)'
    assert_includes scenario, 'write_json(artifact_dir.join("rescue-history.json"), rescue_history)'
    assert_includes scenario, 'write_text(artifact_dir.join("terminal-failure.txt"), terminal_failure_message)'
  end

  test "acceptance scenario emits phase progress events during long benchmark runs" do
    scenario = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes scenario, "def log_capstone_phase"
    assert_includes scenario, 'artifact_dir.join("phase-events.jsonl")'
    assert_includes scenario, 'phase: "host_validation_started"'
    assert_includes scenario, 'phase: "benchmark_reporting_complete"'
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
