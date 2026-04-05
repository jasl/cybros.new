require "test_helper"

class EmbeddedAgents::ConversationSupervision::MaybeDispatchControlIntentTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "dispatches a high-confidence stop request through conversation control" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    assert_difference("ConversationControlRequest.count", 1) do
      decision = EmbeddedAgents::ConversationSupervision::MaybeDispatchControlIntent.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        question: "stop"
      )

      request = ConversationControlRequest.order(:id).last

      assert decision.handled?
      assert_equal "request_turn_interrupt", decision.request_kind
      assert_equal "control_dispatched", decision.response_kind
      assert_equal request.public_id, decision.conversation_control_request.public_id
      assert_equal "request_turn_interrupt", request.request_kind
    end
  end

  test "returns an explanatory response when control is disabled" do
    fixture = prepare_conversation_supervision_context!(control_enabled: false)
    session = create_conversation_supervision_session!(fixture)

    assert_no_difference("ConversationControlRequest.count") do
      decision = EmbeddedAgents::ConversationSupervision::MaybeDispatchControlIntent.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        question: "stop"
      )

      assert decision.handled?
      assert_equal "request_turn_interrupt", decision.request_kind
      assert_equal "control_unavailable", decision.response_kind
      assert_match(/control is not enabled/i, decision.message)
      assert_nil decision.conversation_control_request
    end
  end

  test "returns a denial response when the caller is not allowed to control the conversation" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    outsider = create_user!(installation: fixture.fetch(:installation))

    assert_no_difference("ConversationControlRequest.count") do
      decision = EmbeddedAgents::ConversationSupervision::MaybeDispatchControlIntent.call(
        actor: outsider,
        conversation_supervision_session: session,
        question: "stop"
      )

      assert decision.handled?
      assert_equal "request_turn_interrupt", decision.request_kind
      assert_equal "control_denied", decision.response_kind
      assert_match(/not allowed to control/i, decision.message)
      assert_nil decision.conversation_control_request
    end
  end

  test "keeps ambiguous language in chat mode" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    decision = EmbeddedAgents::ConversationSupervision::MaybeDispatchControlIntent.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      question: "Should we stop after the child comes back?"
    )

    refute decision.handled?
    assert_nil decision.request_kind
  end

  test "dispatches a child-stop request when an active child exists" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    assert_difference("ConversationControlRequest.count", 1) do
      decision = EmbeddedAgents::ConversationSupervision::MaybeDispatchControlIntent.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        question: "让子任务停下"
      )

      request = ConversationControlRequest.order(:id).last

      assert decision.handled?
      assert_equal "request_subagent_close", decision.request_kind
      assert_equal "control_dispatched", decision.response_kind
      assert_equal fixture.fetch(:subagent_session).public_id, request.target_public_id
    end
  end

  test "dispatches a close request for explicit task-close phrasing" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    assert_difference("ConversationControlRequest.count", 1) do
      decision = EmbeddedAgents::ConversationSupervision::MaybeDispatchControlIntent.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        question: "关闭这个任务"
      )

      request = ConversationControlRequest.order(:id).last

      assert decision.handled?
      assert_equal "request_conversation_close", decision.request_kind
      assert_equal "control_dispatched", decision.response_kind
      assert_equal "request_conversation_close", request.request_kind
      assert_equal "archive", request.request_payload["intent_kind"]
    end
  end

  test "uses human-facing wording when a classified control request is rejected at dispatch time" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    decision = EmbeddedAgents::ConversationSupervision::MaybeDispatchControlIntent.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      question: "resume the waiting workflow"
    )

    assert decision.handled?
    assert_equal "resume_waiting_workflow", decision.request_kind
    assert_equal "control_rejected", decision.response_kind
    refute_match(/resume_waiting_workflow|request_turn_interrupt|retry_blocked_step|resume waiting workflow|request turn interrupt|retry blocked step/i, decision.message)
    assert_match(/resume/i, decision.message)
  end
end
