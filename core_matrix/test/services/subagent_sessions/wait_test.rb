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

  test "wait returns semantic supervision rollups for active child work" do
    session = create_terminal_subagent_session!(
      observed_status: "waiting",
      close_state: "open",
      close_outcome_kind: nil,
      close_requested_at: nil,
      close_acknowledged_at: nil
    )
    session.update!(
      supervision_state: "waiting",
      current_focus_summary: "Waiting for alpha review",
      recent_progress_summary: "Handed validation to a child worker",
      waiting_summary: "Waiting for alpha review",
      next_step_hint: "Resume once the review lands",
      last_progress_at: Time.current,
      supervision_payload: {}
    )

    result = SubagentSessions::Wait.call(
      subagent_session: session,
      timeout_seconds: 0,
      poll_interval_seconds: 0.01
    )

    assert_equal "waiting", result.fetch("supervision_state")
    assert_equal "Waiting for alpha review", result.fetch("current_focus_summary")
    assert_equal "Handed validation to a child worker", result.fetch("recent_progress_summary")
    assert_equal "Waiting for alpha review", result.fetch("waiting_summary")
    assert_equal "Resume once the review lands", result.fetch("next_step_hint")
  end

  private

  def create_terminal_subagent_session!(observed_status:, close_state:, close_outcome_kind:, close_requested_at: Time.current, close_acknowledged_at: Time.current)
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version],
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
