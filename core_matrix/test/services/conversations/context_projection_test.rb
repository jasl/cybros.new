require "test_helper"

class Conversations::ContextProjectionTest < ActiveSupport::TestCase
  test "excludes messages marked excluded_from_context while preserving transcript rows" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Keep me in context",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_attachment = create_message_attachment!(
      message: first_turn.selected_input_message,
      filename: "keep.txt"
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Transcript only",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: second_turn.selected_input_message,
      filename: "exclude.txt"
    )

    Messages::UpdateVisibility.call(
      conversation: conversation,
      message: second_turn.selected_input_message,
      excluded_from_context: true
    )

    transcript_ids = Conversations::TranscriptProjection.call(conversation: conversation).map(&:id)
    projection = Conversations::ContextProjection.call(conversation: conversation)

    assert_equal [first_turn.selected_input_message.id, second_turn.selected_input_message.id], transcript_ids
    assert_equal [first_turn.selected_input_message.id], projection.messages.map(&:id)
    assert_equal [first_attachment.id], projection.attachments.map(&:id)
  end

  test "applies ancestor hidden overlays to descendant context projections" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Visible root input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    hidden_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Hidden in descendant",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: hidden_turn.selected_input_message_id
    )

    Messages::UpdateVisibility.call(
      conversation: root,
      message: first_turn.selected_input_message,
      hidden: true
    )

    projection = Conversations::ContextProjection.call(conversation: branch)

    assert_equal [hidden_turn.selected_input_message.id], projection.messages.map(&:id)
  end
end
