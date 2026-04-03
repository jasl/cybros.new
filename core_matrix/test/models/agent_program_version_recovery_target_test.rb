require "test_helper"

class AgentProgramVersionRecoveryTargetTest < ActiveSupport::TestCase
  test "captures the paused-work target deployment and resolved selector snapshot" do
    deployment = AgentProgramVersion.new(fingerprint: "replacement-#{next_test_sequence}")

    target = AgentProgramVersionRecoveryTarget.new(
      agent_program_version: deployment,
      resolved_model_selection_snapshot: { resolved_provider_handle: "openai", normalized_selector: "role:planner" },
      selector_source: :manual_recovery,
      rebind_turn: true
    )

    assert_same deployment, target.agent_program_version
    assert_equal "manual_recovery", target.selector_source
    assert_equal "openai", target.resolved_model_selection_snapshot["resolved_provider_handle"]
    assert_equal "role:planner", target.resolved_model_selection_snapshot["normalized_selector"]
    assert target.rebind_turn?
  end

  test "defensively duplicates the resolved selector snapshot" do
    target = AgentProgramVersionRecoveryTarget.new(
      agent_program_version: AgentProgramVersion.new(fingerprint: "replacement-#{next_test_sequence}"),
      resolved_model_selection_snapshot: { resolved_provider_handle: "openai" },
      selector_source: "conversation",
      rebind_turn: false
    )

    target.resolved_model_selection_snapshot["resolved_provider_handle"] = "codex_subscription"

    assert_equal "openai", target.resolved_model_selection_snapshot["resolved_provider_handle"]
    refute target.rebind_turn?
  end
end
