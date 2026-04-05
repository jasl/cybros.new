require "test_helper"

class EmbeddedAgents::ConversationObservation::AppendMessageTest < ActiveSupport::TestCase
  test "creates a frame-backed observation exchange without mutating the target transcript" do
    fixture = build_observation_fixture!
    session = fixture.fetch(:session)
    result = nil

    assert_difference("ConversationObservationFrame.count", 1) do
      assert_difference("ConversationObservationMessage.count", 2) do
        assert_no_difference(-> { fixture.fetch(:conversation).messages.count }) do
          result = EmbeddedAgents::ConversationObservation::AppendMessage.call(
            actor: fixture.fetch(:user),
            conversation_observation_session: session,
            content: "Summarize current progress for supervisor_status"
          )
        end
      end
    end

    frame = ConversationObservationFrame.order(:id).last
    exchange_messages = session.conversation_observation_messages.order(:created_at).last(2)
    user_message, observer_message = exchange_messages

    assert_equal frame, user_message.conversation_observation_frame
    assert_equal frame, observer_message.conversation_observation_frame
    assert_equal "user", user_message.role
    assert_equal "observer_agent", observer_message.role
    assert_equal "Summarize current progress for supervisor_status", user_message.content
    assert_equal result.dig("human_sidechat", "content"), observer_message.content
    assert_equal result.fetch("assessment"), frame.reload.assessment_payload
    refute result.fetch("assessment").key?("proof_refs")
    assert_equal result.dig("supervisor_status", "proof_refs"), result.dig("human_sidechat", "proof_refs")
  end

  test "requires the session initiator and rejects closed sessions" do
    fixture = build_observation_fixture!
    outsider = create_user!(installation: fixture.fetch(:installation))

    unauthorized_error = assert_raises(EmbeddedAgents::Errors::UnauthorizedObservation) do
      EmbeddedAgents::ConversationObservation::AppendMessage.call(
        actor: outsider,
        conversation_observation_session: fixture.fetch(:session),
        content: "What are you doing?"
      )
    end

    assert_equal "not allowed to observe conversation", unauthorized_error.message

    fixture.fetch(:session).update!(lifecycle_state: "closed")

    closed_error = assert_raises(EmbeddedAgents::Errors::ClosedObservationSession) do
      EmbeddedAgents::ConversationObservation::AppendMessage.call(
        actor: fixture.fetch(:user),
        conversation_observation_session: fixture.fetch(:session),
        content: "What are you doing?"
      )
    end

    assert_equal "observation session is closed", closed_error.message
  end

  private

  def build_observation_fixture!
    context = build_canonical_variable_context!
    conversation = context.fetch(:conversation)
    attach_selected_output!(context.fetch(:turn), content: "Earlier answer")
    context.fetch(:turn).update!(lifecycle_state: "completed")
    context.fetch(:workflow_run).update!(lifecycle_state: "completed")

    current_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current progress update?",
      agent_program_version: context.fetch(:agent_program_version),
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: current_turn, wait_state: "ready", wait_reason_payload: {})
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "implement",
      node_type: "turn_step",
      lifecycle_state: "running",
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      started_at: 2.minutes.ago,
      metadata: {}
    )
    child_conversation = create_conversation_record!(
      installation: context.fetch(:installation),
      workspace: context.fetch(:workspace),
      parent_conversation: conversation,
      kind: "fork",
      execution_runtime: context.fetch(:execution_runtime),
      agent_program_version: context.fetch(:agent_program_version),
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context.fetch(:installation),
      owner_conversation: conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "subagent_barrier",
      wait_reason_payload: {},
      waiting_since_at: 1.minute.ago
    )
    ConversationRuntime::PublishEvent.call(
      conversation: conversation,
      turn: current_turn,
      event_kind: "runtime.workflow_node.started",
      payload: {
        "workflow_run_id" => workflow_run.public_id,
        "workflow_node_id" => workflow_node.public_id,
        "state" => "running",
      }
    )

    session = ConversationObservationSession.create!(
      installation: context.fetch(:installation),
      target_conversation: conversation,
      initiator: context.fetch(:user),
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "observe" => true, "control_enabled" => false }
    )

    context.merge(
      installation: context.fetch(:installation),
      user: context.fetch(:user),
      conversation: conversation,
      current_turn: current_turn,
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      session: session
    )
  end
end
