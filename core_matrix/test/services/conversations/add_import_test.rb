require "test_helper"

class Conversations::AddImportTest < ActiveSupport::TestCase
  test "creates quoted context imports by inferring the summary source conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Root input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    summary_segment = ConversationSummarySegment.create!(
      installation: conversation.installation,
      conversation: conversation,
      start_message: turn.selected_input_message,
      end_message: turn.selected_input_message,
      content: "Quoted summary"
    )

    import = Conversations::AddImport.call(
      conversation: conversation,
      kind: "quoted_context",
      summary_segment: summary_segment
    )

    assert import.persisted?
    assert import.quoted_context?
    assert_equal conversation, import.source_conversation
    assert_equal summary_segment, import.summary_segment
  end

  test "rejects branch prefix imports that do not match the branch anchor" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "First input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Second input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: first_turn.selected_input_message.id
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::AddImport.call(
        conversation: branch,
        kind: "branch_prefix",
        source_conversation: root,
        source_message: second_turn.selected_input_message
      )
    end

    assert_includes error.record.errors[:source_message], "must match the branch anchor message"
  end

  test "rejects imports for pending delete conversations" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Root input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    summary_segment = ConversationSummarySegment.create!(
      installation: conversation.installation,
      conversation: conversation,
      start_message: turn.selected_input_message,
      end_message: turn.selected_input_message,
      content: "Quoted summary"
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::AddImport.call(
        conversation: conversation,
        kind: "quoted_context",
        summary_segment: summary_segment
      )
    end

    assert_instance_of ConversationImport, error.record
    assert error.record.quoted_context?
    assert_equal conversation, error.record.conversation
    assert_equal summary_segment, error.record.summary_segment
    assert_includes error.record.errors[:deletion_state], "must be retained before adding imports"
  end

  test "rejects quoted context imports whose source message is outside the source transcript projection" do
    context = create_workspace_context!
    source_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    foreign_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    target_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: foreign_conversation,
      content: "Foreign input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::AddImport.call(
        conversation: target_conversation,
        kind: "quoted_context",
        source_conversation: source_conversation,
        source_message: foreign_turn.selected_input_message
      )
    end

    assert_includes error.record.errors[:source_message], "must be present in the source conversation transcript projection"
  end
end
