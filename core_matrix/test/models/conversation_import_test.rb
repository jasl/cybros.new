require "test_helper"

class ConversationImportTest < ActiveSupport::TestCase
  test "supports branch prefix merge summary and quoted context imports" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    message = turn.selected_input_message
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: message.id
    )
    summary_segment = ConversationSummarySegment.create!(
      installation: root.installation,
      conversation: root,
      start_message: message,
      end_message: message,
      content: "Condensed root context"
    )

    branch_prefix = branch.conversation_imports.find_by!(kind: "branch_prefix")
    merge_summary = ConversationImport.new(
      installation: root.installation,
      conversation: root,
      kind: "merge_summary",
      summary_segment: summary_segment
    )
    quoted_context = ConversationImport.new(
      installation: root.installation,
      conversation: root,
      kind: "quoted_context",
      summary_segment: summary_segment
    )

    assert branch_prefix.valid?
    assert merge_summary.valid?
    assert quoted_context.valid?
  end

  test "requires source references that match the import kind" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    invalid = ConversationImport.new(
      installation: conversation.installation,
      conversation: conversation,
      kind: "branch_prefix"
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:source_conversation], "must exist for branch_prefix imports"
    assert_includes invalid.errors[:source_message], "must exist for branch_prefix imports"
  end

  test "quoted context imports stay valid when the source message is hidden from the visible projection" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Root input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    message = turn.selected_input_message
    quoted_context = ConversationImport.create!(
      installation: conversation.installation,
      conversation: conversation,
      kind: "quoted_context",
      source_message: message
    )
    ConversationMessageVisibility.create!(
      installation: conversation.installation,
      conversation: conversation,
      message: message,
      hidden: true
    )

    assert_predicate quoted_context.reload, :valid?
  end
end
