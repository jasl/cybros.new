require "test_helper"

class ExecutionIdentityRecoveryTargetTest < ActiveSupport::TestCase
  test "captures the paused-work target agent_definition_version and resolved selector snapshot" do
    agent_definition_version = AgentDefinitionVersion.new(definition_fingerprint: "replacement-#{next_test_sequence}")

    target = ExecutionIdentityRecoveryTarget.new(
      agent_definition_version: agent_definition_version,
      resolved_model_selection_snapshot: { resolved_provider_handle: "openai", normalized_selector: "role:planner" },
      selector_source: :manual_recovery,
      rebind_turn: true
    )

    assert_same agent_definition_version, target.agent_definition_version
    assert_equal "manual_recovery", target.selector_source
    assert_equal "openai", target.resolved_model_selection_snapshot["resolved_provider_handle"]
    assert_equal "role:planner", target.resolved_model_selection_snapshot["normalized_selector"]
    assert target.rebind_turn?
  end

  test "defensively duplicates the resolved selector snapshot" do
    target = ExecutionIdentityRecoveryTarget.new(
      agent_definition_version: AgentDefinitionVersion.new(definition_fingerprint: "replacement-#{next_test_sequence}"),
      resolved_model_selection_snapshot: { resolved_provider_handle: "openai" },
      selector_source: "conversation",
      rebind_turn: false
    )

    target.resolved_model_selection_snapshot["resolved_provider_handle"] = "codex_subscription"

    assert_equal "openai", target.resolved_model_selection_snapshot["resolved_provider_handle"]
    refute target.rebind_turn?
  end
end
