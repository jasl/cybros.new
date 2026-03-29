require "test_helper"

class Conversations::ValidateHistoricalAnchorTest < ActiveSupport::TestCase
  test "requires anchors for branch and checkpoint conversations" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    %w[branch checkpoint].each do |kind|
      record = Conversation.new(kind: kind, parent_conversation: root)

      error = assert_raises(ActiveRecord::RecordInvalid) do
        Conversations::ValidateHistoricalAnchor.call(
          parent: root,
          kind: kind,
          historical_anchor_message_id: nil,
          record: record
        )
      end

      assert_same record, error.record
      assert_includes error.record.errors[:historical_anchor_message_id], "must exist"
    end
  end

  test "accepts anchors inherited into the parent transcript history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Inherited anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    parent_branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    anchor = Conversations::ValidateHistoricalAnchor.call(
      parent: parent_branch,
      kind: "branch",
      historical_anchor_message_id: root_turn.selected_input_message_id,
      record: Conversation.new(kind: "branch", parent_conversation: parent_branch)
    )

    assert_equal root_turn.selected_input_message, anchor
  end

  test "adds record errors when the anchor is outside the parent history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    other_root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: other_root,
      content: "Foreign anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    record = Conversation.new(kind: "branch", parent_conversation: root)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateHistoricalAnchor.call(
        parent: root,
        kind: "branch",
        historical_anchor_message_id: foreign_turn.selected_input_message_id,
        record: record
      )
    end

    assert_same record, error.record
    assert_includes error.record.errors[:historical_anchor_message_id], "must belong to the parent conversation history"
  end
end
