require "test_helper"

class ConversationStructureFlowTest < ActionDispatch::IntegrationTest
  test "interactive conversations support lineage while automation stays root only" do
    context = create_workspace_context!
    workspace = context[:workspace]

    root = Conversations::CreateRoot.call(
      workspace: workspace,
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch_anchor = attach_selected_output!(root_turn, content: "Root output")
    root_turn.update!(lifecycle_state: "completed")
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: branch_anchor.id
    )
    branch_turn = Turns::StartUserTurn.call(
      conversation: branch,
      content: "Branch input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch_turn.update!(lifecycle_state: "completed")
    fork = Conversations::CreateFork.call(parent: root)
    checkpoint = Conversations::CreateCheckpoint.call(
      parent: branch,
      historical_anchor_message_id: branch_turn.selected_input_message_id
    )

    Conversations::Archive.call(conversation: branch)
    Conversations::Unarchive.call(conversation: branch)

    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: workspace,
    )

    assert_equal "active", branch.reload.lifecycle_state
    assert_equal [[root.id, checkpoint.id, 2], [branch.id, checkpoint.id, 1], [checkpoint.id, checkpoint.id, 0]],
      ConversationClosure.where(descendant_conversation: checkpoint)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(
        parent: automation_root,
        historical_anchor_message_id: branch_anchor.id
      )
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateFork.call(parent: automation_root)
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(
        parent: automation_root,
        historical_anchor_message_id: branch_anchor.id
      )
    end
  end
end
