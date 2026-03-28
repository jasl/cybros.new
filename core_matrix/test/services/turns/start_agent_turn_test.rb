require "test_helper"

class Turns::StartAgentTurnTest < ActiveSupport::TestCase
  test "creates an active delegated turn on agent addressable conversations" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
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
      agent_deployment: context[:agent_deployment],
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
    assert_equal "Conversation", turn.source_ref_type
    assert_equal owner_conversation.public_id, turn.source_ref_id
    assert_instance_of UserMessage, turn.selected_input_message
    assert_equal "Investigate this", turn.selected_input_message.content
  end

  test "rejects owner addressable conversations" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartAgentTurn.call(
        conversation: owner_conversation,
        content: "Blocked",
        sender_kind: "owner_agent",
        sender_conversation: owner_conversation,
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:addressability], "must be agent_addressable for agent turn entry"
  end

  private

  def create_agent_addressable_child_conversation!(context:, owner_conversation:, profile_key:)
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "thread",
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      addressability: "agent_addressable"
    )
    SubagentSession.create!(
      installation: context[:installation],
      conversation: child_conversation,
      owner_conversation: owner_conversation,
      scope: "conversation",
      profile_key: profile_key,
      depth: 0
    )

    child_conversation
  end
end
