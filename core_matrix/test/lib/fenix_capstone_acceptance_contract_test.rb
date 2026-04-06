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
