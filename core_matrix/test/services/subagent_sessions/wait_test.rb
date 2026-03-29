require "test_helper"

class SubagentSessions::WaitTest < ActiveSupport::TestCase
  test "wait short-circuits on terminal durable state" do
    session = create_terminal_subagent_session!(
      observed_status: "completed",
      close_state: "closed",
      close_outcome_kind: "graceful"
    )

    result = SubagentSessions::Wait.call(
      subagent_session: session,
      timeout_seconds: 5,
      poll_interval_seconds: 0.01
    )

    assert_equal false, result.fetch("timed_out")
    assert_equal session.public_id, result.fetch("subagent_session_id")
    assert_equal "closed", result.fetch("derived_close_status")
    assert_equal "completed", result.fetch("observed_status")
    assert_equal "closed", result.fetch("close_state")
  end

  test "wait times out cleanly" do
    session = create_terminal_subagent_session!(
      observed_status: "running",
      close_state: "open",
      close_outcome_kind: nil,
      close_requested_at: nil,
      close_acknowledged_at: nil
    )

    result = SubagentSessions::Wait.call(
      subagent_session: session,
      timeout_seconds: 0,
      poll_interval_seconds: 0.01
    )

    assert_equal true, result.fetch("timed_out")
    assert_equal "open", result.fetch("derived_close_status")
    assert_equal "running", result.fetch("observed_status")
    assert_equal "open", result.fetch("close_state")
    assert_equal "open", session.reload.derived_close_status
    assert_equal "running", session.observed_status
  end

  private

  def create_terminal_subagent_session!(observed_status:, close_state:, close_outcome_kind:, close_requested_at: Time.current, close_acknowledged_at: Time.current)
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      addressability: "agent_addressable"
    )

    SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: observed_status,
      close_state: close_state,
      close_reason_kind: close_state == "open" ? nil : "turn_interrupt",
      close_requested_at: close_requested_at,
      close_grace_deadline_at: close_requested_at&.+(30.seconds),
      close_force_deadline_at: close_requested_at&.+(60.seconds),
      close_acknowledged_at: close_acknowledged_at,
      close_outcome_kind: close_outcome_kind,
      close_outcome_payload: {}
    )
  end
end
