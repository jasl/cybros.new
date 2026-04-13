require "test_helper"

class ConversationControlRequestTest < ActiveSupport::TestCase
  test "creates an auditable control request with public id targets and result payloads" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )

    request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: session,
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      request_kind: "request_turn_interrupt",
      target_kind: "conversation",
      target_public_id: conversation.public_id,
      lifecycle_state: "queued",
      request_payload: { "reason" => "operator_request" },
      result_payload: {},
      completed_at: nil
    )

    assert request.public_id.present?
    assert_equal request, ConversationControlRequest.find_by_public_id!(request.public_id)
    assert_equal session, request.conversation_supervision_session
    assert_equal conversation.public_id, request.target_public_id
    assert_equal "request_turn_interrupt", request.request_kind
    assert_equal({}, request.result_payload)
    assert_equal request, conversation.conversation_control_requests.last
  end

  test "requires the session and target conversation to agree" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    other_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )

    request = ConversationControlRequest.new(
      installation: context[:installation],
      conversation_supervision_session: session,
      target_conversation: other_conversation,
      request_kind: "request_conversation_close",
      target_kind: "conversation",
      target_public_id: other_conversation.public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )

    assert_not request.valid?
    assert_includes request.errors[:target_conversation], "must match the supervision session target conversation"
  end

  test "requires duplicated owner context to match the target conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )
    foreign = create_workspace_context!

    request = ConversationControlRequest.new(
      installation: context[:installation],
      conversation_supervision_session: session,
      target_conversation: conversation,
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id,
      request_kind: "request_status_refresh",
      target_kind: "conversation",
      target_public_id: conversation.public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )

    assert_not request.valid?
    assert_includes request.errors[:user], "must match the target conversation user"
    assert_includes request.errors[:workspace], "must match the target conversation workspace"
    assert_includes request.errors[:agent], "must match the target conversation agent"
  end

  test "has guidance projection indexes for conversation and subagent targets" do
    indexes = ActiveRecord::Base.connection.indexes(:conversation_control_requests)

    assert indexes.any? { |index|
      index.columns == %w[installation_id request_kind lifecycle_state target_conversation_id completed_at]
    }
    assert indexes.any? { |index|
      index.columns == %w[installation_id request_kind lifecycle_state target_public_id completed_at]
    }
  end
end
