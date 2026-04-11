require "test_helper"

class AgentSnapshotRecoveryTargetTest < ActiveSupport::TestCase
  test "captures the paused-work target agent_snapshot and resolved selector snapshot" do
    agent_snapshot = AgentSnapshot.new(fingerprint: "replacement-#{next_test_sequence}")

    target = AgentSnapshotRecoveryTarget.new(
      agent_snapshot: agent_snapshot,
      resolved_model_selection_snapshot: { resolved_provider_handle: "openai", normalized_selector: "role:planner" },
      selector_source: :manual_recovery,
      rebind_turn: true
    )

    assert_same agent_snapshot, target.agent_snapshot
    assert_equal "manual_recovery", target.selector_source
    assert_equal "openai", target.resolved_model_selection_snapshot["resolved_provider_handle"]
    assert_equal "role:planner", target.resolved_model_selection_snapshot["normalized_selector"]
    assert target.rebind_turn?
  end

  test "defensively duplicates the resolved selector snapshot" do
    target = AgentSnapshotRecoveryTarget.new(
      agent_snapshot: AgentSnapshot.new(fingerprint: "replacement-#{next_test_sequence}"),
      resolved_model_selection_snapshot: { resolved_provider_handle: "openai" },
      selector_source: "conversation",
      rebind_turn: false
    )

    target.resolved_model_selection_snapshot["resolved_provider_handle"] = "codex_subscription"

    assert_equal "openai", target.resolved_model_selection_snapshot["resolved_provider_handle"]
    refute target.rebind_turn?
  end
end
