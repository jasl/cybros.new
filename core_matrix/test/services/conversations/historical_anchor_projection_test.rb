require "test_helper"

class Conversations::HistoricalAnchorProjectionTest < ActiveSupport::TestCase
  test "returns inherited transcript plus local source provenance for output anchors" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )
    branch_turn = Turns::StartUserTurn.call(
      conversation: branch,
      content: "Branch input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch_output = attach_selected_output!(branch_turn, content: "Branch output")

    projection = Conversations::HistoricalAnchorProjection.call(
      conversation: branch,
      message: branch_output
    )

    assert_equal ["Root input", "Branch input", "Branch output"], projection.map(&:content)
  end

  test "rejects local output anchors that lost source input provenance" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )
    branch_turn = Turns::StartUserTurn.call(
      conversation: branch,
      content: "Branch input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    broken_output = AgentMessage.create!(
      installation: branch.installation,
      conversation: branch,
      turn: branch_turn,
      role: "agent",
      slot: "output",
      variant_index: 0,
      content: "Broken output"
    )

    error = assert_raises(ActiveRecord::RecordNotFound) do
      Conversations::HistoricalAnchorProjection.call(
        conversation: branch,
        message: broken_output
      )
    end

    assert_equal "historical anchor is missing source input provenance", error.message
  end
end
