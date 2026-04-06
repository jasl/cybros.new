require "test_helper"

class ConversationControl::DispatchRequestTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "request_turn_interrupt routes through Conversations::RequestTurnInterrupt" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    request = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "request_turn_interrupt",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )
    captured = nil

    original_call = Conversations::RequestTurnInterrupt.method(:call)
    Conversations::RequestTurnInterrupt.singleton_class.define_method(:call) do |turn:, occurred_at:, conversation_control_request: nil|
      captured = [turn.public_id, conversation_control_request&.public_id]
      turn
    end

    begin
      ConversationControl::DispatchRequest.call(conversation_control_request: request)
    ensure
      Conversations::RequestTurnInterrupt.singleton_class.define_method(:call, original_call)
    end

    assert_equal [fixture.fetch(:current_turn).public_id, request.public_id], captured
  end

  test "request_conversation_close routes through Conversations::RequestClose" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    request = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "request_conversation_close",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "queued",
      request_payload: { "intent_kind" => "archive" },
      result_payload: {}
    )
    captured = nil

    original_call = Conversations::RequestClose.method(:call)
    Conversations::RequestClose.singleton_class.define_method(:call) do |conversation:, intent_kind:, occurred_at:, conversation_control_request: nil|
      captured = [conversation.public_id, intent_kind, conversation_control_request&.public_id]
      conversation
    end

    begin
      ConversationControl::DispatchRequest.call(conversation_control_request: request)
    ensure
      Conversations::RequestClose.singleton_class.define_method(:call, original_call)
    end

    assert_equal [fixture.fetch(:conversation).public_id, "archive", request.public_id], captured
  end

  test "request_subagent_close routes through SubagentSessions::RequestClose" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    request = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "request_subagent_close",
      target_kind: "subagent_session",
      target_public_id: fixture.fetch(:subagent_session).public_id,
      lifecycle_state: "queued",
      request_payload: { "strictness" => "graceful" },
      result_payload: {}
    )
    captured = nil

    original_call = SubagentSessions::RequestClose.method(:call)
    SubagentSessions::RequestClose.singleton_class.define_method(:call) do |subagent_session:, request_kind:, reason_kind:, strictness:, conversation_control_request: nil, **_rest|
      captured = [subagent_session.public_id, request_kind, reason_kind, strictness, conversation_control_request&.public_id]
      subagent_session
    end

    begin
      ConversationControl::DispatchRequest.call(conversation_control_request: request)
    ensure
      SubagentSessions::RequestClose.singleton_class.define_method(:call, original_call)
    end

    assert_equal [
      fixture.fetch(:subagent_session).public_id,
      "request_subagent_close",
      "supervision_subagent_close_requested",
      "graceful",
      request.public_id,
    ], captured
  end

  test "resume_waiting_workflow routes through Workflows::ManualResume when the workflow is paused for manual recovery" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    fixture.fetch(:workflow_run).update!(
      wait_state: "waiting",
      wait_reason_kind: "manual_recovery_required",
      wait_reason_payload: {},
      waiting_since_at: Time.current,
      recovery_state: "paused_agent_unavailable"
    )
    session = create_conversation_supervision_session!(fixture)
    request = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "resume_waiting_workflow",
      target_kind: "workflow_run",
      target_public_id: fixture.fetch(:workflow_run).public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )
    captured = nil

    original_call = Workflows::ManualResume.method(:call)
    Workflows::ManualResume.singleton_class.define_method(:call) do |workflow_run:, deployment:, actor:, conversation_control_request: nil, **_rest|
      captured = [workflow_run.public_id, deployment.public_id, actor.public_id, conversation_control_request&.public_id]
      workflow_run
    end

    begin
      ConversationControl::DispatchRequest.call(conversation_control_request: request)
    ensure
      Workflows::ManualResume.singleton_class.define_method(:call, original_call)
    end

    assert_equal [
      fixture.fetch(:workflow_run).public_id,
      fixture.fetch(:agent_program_version).public_id,
      fixture.fetch(:user).public_id,
      request.public_id,
    ], captured
  end

  test "resume_waiting_workflow is rejected when the workflow is not paused for manual recovery" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    request = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "resume_waiting_workflow",
      target_kind: "workflow_run",
      target_public_id: fixture.fetch(:workflow_run).public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )

    ConversationControl::DispatchRequest.call(conversation_control_request: request)

    assert_equal "rejected", request.reload.lifecycle_state
    assert_equal "workflow is not paused for manual recovery", request.result_payload["rejection_reason"]
  end

  test "retry_blocked_step routes through Workflows::StepRetry when the workflow is waiting on a retryable step failure" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    fixture.fetch(:workflow_run).update!(
      wait_state: "waiting",
      wait_reason_kind: "retryable_failure",
      wait_reason_payload: {},
      wait_failure_kind: "tool_failure",
      wait_retry_scope: "step",
      wait_attempt_no: 1,
      waiting_since_at: Time.current
    )
    session = create_conversation_supervision_session!(fixture)
    request = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "retry_blocked_step",
      target_kind: "workflow_run",
      target_public_id: fixture.fetch(:workflow_run).public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )
    captured = nil

    original_call = Workflows::StepRetry.method(:call)
    Workflows::StepRetry.singleton_class.define_method(:call) do |workflow_run:, conversation_control_request: nil, **_rest|
      captured = [workflow_run.public_id, conversation_control_request&.public_id]
      workflow_run
    end

    begin
      ConversationControl::DispatchRequest.call(conversation_control_request: request)
    ensure
      Workflows::StepRetry.singleton_class.define_method(:call, original_call)
    end

    assert_equal [fixture.fetch(:workflow_run).public_id, request.public_id], captured
  end

  test "retry_blocked_step is rejected when the workflow wait state does not permit a step retry" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    request = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "retry_blocked_step",
      target_kind: "workflow_run",
      target_public_id: fixture.fetch(:workflow_run).public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )

    ConversationControl::DispatchRequest.call(conversation_control_request: request)

    assert_equal "rejected", request.reload.lifecycle_state
    assert_equal "workflow wait state does not permit step retry", request.result_payload["rejection_reason"]
  end
end
