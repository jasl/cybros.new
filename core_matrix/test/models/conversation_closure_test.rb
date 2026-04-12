require "test_helper"

class ConversationClosureTest < ActiveSupport::TestCase
  test "stores unique ancestor descendant pairs with non negative depth" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: anchor_turn.selected_input_message_id
    )

    duplicate = ConversationClosure.new(
      installation: root.installation,
      ancestor_conversation: root,
      descendant_conversation: branch,
      depth: 1
    )
    negative_depth = ConversationClosure.new(
      installation: root.installation,
      ancestor_conversation: root,
      descendant_conversation: branch,
      depth: -1
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ancestor_conversation_id], "has already been taken"
    assert_not negative_depth.valid?
    assert_includes negative_depth.errors[:depth], "must be greater than or equal to 0"
  end
end
