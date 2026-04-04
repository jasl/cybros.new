require "test_helper"

class ConversationObservationMessageTest < ActiveSupport::TestCase
  test "supports user observer_agent and system roles for a session and frame" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )
    session = ConversationObservationSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "mode" => "observe_only" }
    )
    frame = ConversationObservationFrame.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: session,
      anchor_turn_public_id: "turn_public",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      wait_state: "ready",
      active_subagent_session_public_ids: [],
      runtime_state_snapshot: {},
      assessment_payload: {}
    )

    user_message = ConversationObservationMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: session,
      conversation_observation_frame: frame,
      role: "user",
      content: "What are you doing?",
      metadata: {}
    )

    observer_message = ConversationObservationMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: session,
      conversation_observation_frame: frame,
      role: "observer_agent",
      content: "I am waiting on provider execution.",
      metadata: { "kind" => "supervisor_status" }
    )

    system_message = ConversationObservationMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: session,
      conversation_observation_frame: frame,
      role: "system",
      content: "Observation note",
      metadata: {}
    )

    assert_equal [user_message, observer_message, system_message], ConversationObservationMessage.order(:id)
    assert_equal "user", user_message.role
    assert_equal "observer_agent", observer_message.role
    assert_equal "system", system_message.role
  end

  test "requires the message to stay on the session target conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )
    other_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )
    session = ConversationObservationSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {}
    )
    frame = ConversationObservationFrame.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: session,
      anchor_turn_public_id: "turn_public",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      wait_state: "ready",
      active_subagent_session_public_ids: [],
      runtime_state_snapshot: {},
      assessment_payload: {}
    )

    message = ConversationObservationMessage.new(
      installation: context[:installation],
      target_conversation: other_conversation,
      conversation_observation_session: session,
      conversation_observation_frame: frame,
      role: "user",
      content: "Mismatch",
      metadata: {}
    )

    assert_not message.valid?
    assert_includes message.errors[:target_conversation], "must match the observation session target conversation"
  end

  test "requires metadata to be a hash" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )
    session = ConversationObservationSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {}
    )
    frame = ConversationObservationFrame.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: session,
      anchor_turn_public_id: "turn_public",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      wait_state: "ready",
      active_subagent_session_public_ids: [],
      runtime_state_snapshot: {},
      assessment_payload: {}
    )

    message = ConversationObservationMessage.new(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: session,
      conversation_observation_frame: frame,
      role: "user",
      content: "Mismatch",
      metadata: "not a hash"
    )

    assert_not message.valid?
    assert_includes message.errors[:metadata], "must be a hash"
  end
end
