require "test_helper"

class SubagentConnections::WaitTest < ActiveSupport::TestCase
  test "wait short-circuits on terminal durable state" do
    session = create_terminal_subagent_connection!(
      observed_status: "completed",
      close_state: "closed",
      close_outcome_kind: "graceful"
    )

    result = SubagentConnections::Wait.call(
      subagent_connection: session,
      timeout_seconds: 5,
      poll_interval_seconds: 0.01
    )

    assert_equal false, result.fetch("timed_out")
    assert_equal session.public_id, result.fetch("subagent_connection_id")
    assert_equal "closed", result.fetch("derived_close_status")
    assert_equal "completed", result.fetch("observed_status")
    assert_equal "closed", result.fetch("close_state")
  end

  test "wait times out cleanly" do
    session = create_terminal_subagent_connection!(
      observed_status: "running",
      close_state: "open",
      close_outcome_kind: nil,
      close_requested_at: nil,
      close_acknowledged_at: nil
    )

    result = SubagentConnections::Wait.call(
      subagent_connection: session,
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
    session = create_terminal_subagent_connection!(
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

    result = SubagentConnections::Wait.call(
      subagent_connection: session,
      timeout_seconds: 0,
      poll_interval_seconds: 0.01
    )

    assert_equal "waiting", result.fetch("supervision_state")
    assert_equal "Waiting for alpha review", result.fetch("current_focus_summary")
    assert_equal "Handed validation to a child worker", result.fetch("recent_progress_summary")
    assert_equal "Waiting for alpha review", result.fetch("waiting_summary")
    assert_equal "Resume once the review lands", result.fetch("next_step_hint")
  end

  test "wait returns a neutral result envelope for completed child work" do
    session = create_terminal_subagent_connection!(
      observed_status: "completed",
      close_state: "open",
      close_outcome_kind: nil,
      close_requested_at: nil,
      close_acknowledged_at: nil
    )
    child_turn = Turns::StartAgentTurn.call(
      conversation: session.conversation,
      content: "Finish the child work",
      sender_kind: "owner_agent",
      sender_conversation: session.owner_conversation,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_workflow_run = create_workflow_run!(turn: child_turn)
    child_workflow_node = create_workflow_node!(
      workflow_run: child_workflow_run,
      node_key: "subagent_step",
      node_type: "subagent_step",
      lifecycle_state: "completed",
      decision_source: "agent",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    child_task_run = create_agent_task_run!(
      workflow_node: child_workflow_node,
      kind: "subagent_step",
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      request_summary: "Finish the child work",
      task_payload: { "delivery_kind" => "subagent_spawn" },
      origin_turn: session.origin_turn,
      subagent_connection: session,
      terminal_payload: { "output" => "Child work finished cleanly" }
    )

    result = SubagentConnections::Wait.call(
      subagent_connection: session,
      timeout_seconds: 5,
      poll_interval_seconds: 0.01
    )

    envelope = result.fetch("result_envelope")

    assert_equal session.conversation.public_id, envelope.fetch("conversation_id")
    assert_equal child_turn.public_id, envelope.fetch("turn_id")
    assert_equal child_workflow_run.public_id, envelope.fetch("workflow_run_id")
    assert_equal child_task_run.public_id, envelope.fetch("agent_task_run_id")
    assert_equal "completed", envelope.fetch("lifecycle_state")
    assert_equal "Child work finished cleanly", envelope.fetch("output")
  end

  private

  def create_terminal_subagent_connection!(observed_status:, close_state:, close_outcome_kind:, close_requested_at: Time.current, close_acknowledged_at: Time.current)
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      addressability: "agent_addressable"
    )

    SubagentConnection.create!(
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
