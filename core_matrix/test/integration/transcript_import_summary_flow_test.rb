require "test_helper"

class TranscriptImportSummaryFlowTest < ActionDispatch::IntegrationTest
  test "branch imports summaries and fork-point protections preserve transcript support invariants" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    root_message = root_turn.selected_input_message

    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_message.id
    )

    branch_prefix = branch.conversation_imports.find_by!(kind: "branch_prefix")

    assert_equal root, branch_prefix.source_conversation
    assert_equal root_message, branch_prefix.source_message
    assert_empty branch.messages

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::EditTailInput.call(turn: root_turn, content: "Fork point rewrite")
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: root,
        message: root_message,
        hidden: true
      )
    end

    branch_error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: branch,
        message: root_message,
        excluded_from_context: true
      )
    end

    assert_includes branch_error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
    assert_equal [root_message.id], Conversations::ContextProjection.call(conversation: branch).messages.map(&:id)

    summary_segment = ConversationSummaries::CreateSegment.call(
      conversation: root,
      start_message: root_message,
      end_message: root_message,
      content: "Root summary"
    )
    quoted_context = Conversations::AddImport.call(
      conversation: root,
      kind: "quoted_context",
      summary_segment: summary_segment
    )

    assert_equal summary_segment, quoted_context.summary_segment
    assert_equal root, quoted_context.source_conversation
  end
end
