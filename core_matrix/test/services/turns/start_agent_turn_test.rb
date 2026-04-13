require "test_helper"

class Turns::StartAgentTurnTest < ActiveSupport::TestCase
  test "creates an active delegated turn on agent addressable conversations" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    child_conversation = create_agent_addressable_child_conversation!(
      context: context,
      owner_conversation: owner_conversation,
      profile_key: "researcher"
    )

    turn = Turns::StartAgentTurn.call(
      conversation: child_conversation,
      content: "Investigate this",
      sender_kind: "owner_agent",
      sender_conversation: owner_conversation,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.active?
    assert_equal "system_internal", turn.origin_kind
    assert_equal(
      {
        "sender_kind" => "owner_agent",
        "sender_conversation_id" => owner_conversation.public_id,
      },
      turn.origin_payload
    )
    assert_equal context[:agent_definition_version], turn.agent_definition_version
    assert_equal context[:execution_runtime], turn.execution_runtime
    assert_equal context[:execution_runtime].current_execution_runtime_version, turn.execution_runtime_version
    assert_equal(context[:agent].agent_config_state&.version || 1, turn.agent_config_version)
    assert_equal(
      context[:agent].agent_config_state&.content_fingerprint || context[:agent_definition_version].definition_fingerprint,
      turn.agent_config_content_fingerprint
    )
    assert_equal "Conversation", turn.source_ref_type
    assert_equal owner_conversation.public_id, turn.source_ref_id
    assert_instance_of UserMessage, turn.selected_input_message
    assert_equal "Investigate this", turn.selected_input_message.content
    assert_equal turn, child_conversation.reload.latest_turn
    assert_equal turn, child_conversation.latest_active_turn
    assert_equal turn.selected_input_message, child_conversation.latest_message
    assert_equal turn.selected_input_message.created_at.to_i, child_conversation.last_activity_at.to_i
  end

  test "rejects owner addressable conversations" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartAgentTurn.call(
        conversation: owner_conversation,
        content: "Blocked",
        sender_kind: "owner_agent",
        sender_conversation: owner_conversation,
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:addressability], "must be agent_addressable for agent turn entry"
  end

  test "rejects unexpected keyword arguments" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    child_conversation = create_agent_addressable_child_conversation!(
      context: context,
      owner_conversation: owner_conversation,
      profile_key: "researcher"
    )

    assert_raises(ArgumentError) do
      Turns::StartAgentTurn.call(
        conversation: child_conversation,
        content: "Investigate this",
        sender_kind: "owner_agent",
        sender_conversation: owner_conversation,
        agent_definition_version: context[:agent_definition_version],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end
  end

  test "starts an agent turn within twenty-seven SQL queries" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    child_conversation = create_agent_addressable_child_conversation!(
      context: context,
      owner_conversation: owner_conversation,
      profile_key: "researcher"
    )

    assert_sql_query_count_at_most(27) do
      turn = Turns::StartAgentTurn.call(
        conversation: child_conversation,
        content: "Investigate this",
        sender_kind: "owner_agent",
        sender_conversation: owner_conversation,
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )

      assert_equal owner_conversation.public_id, turn.source_ref_id
    end
  end

  private

  def create_agent_addressable_child_conversation!(context:, owner_conversation:, profile_key:)
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      addressability: "agent_addressable"
    )
    SubagentConnection.create!(
      installation: context[:installation],
      conversation: child_conversation,
      owner_conversation: owner_conversation,
      user: child_conversation.user,
      workspace: child_conversation.workspace,
      agent: child_conversation.agent,
      scope: "conversation",
      profile_key: profile_key,
      depth: 0
    )

    child_conversation
  end
end
