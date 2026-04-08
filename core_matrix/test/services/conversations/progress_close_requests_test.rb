require "test_helper"

class Conversations::ProgressCloseRequestsTest < ActiveSupport::TestCase
  test "escalates grace-expired close requests to forced strictness" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    mailbox_item = AgentControl::CreateResourceCloseRequest.call(
      resource: process_run,
      request_kind: "archive",
      reason_kind: "conversation_archived",
      strictness: "graceful",
      grace_deadline_at: 2.minutes.ago,
      force_deadline_at: 1.minute.from_now
    )

    Conversations::ProgressCloseRequests.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "forced", mailbox_item.reload.payload["strictness"]
    assert_equal "queued", mailbox_item.status
  end

  test "does not touch active close requests once the resource is already closed" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    mailbox_item = AgentControl::CreateResourceCloseRequest.call(
      resource: process_run,
      request_kind: "archive",
      reason_kind: "conversation_archived",
      strictness: "graceful",
      grace_deadline_at: 2.minutes.ago,
      force_deadline_at: 1.minute.from_now
    )
    process_run.update!(
      close_state: "closed",
      close_reason_kind: "conversation_archived",
      close_requested_at: 2.minutes.ago,
      close_grace_deadline_at: 90.seconds.ago,
      close_force_deadline_at: 1.minute.from_now,
      close_outcome_kind: "graceful",
      close_outcome_payload: { "source" => "test" }
    )

    Conversations::ProgressCloseRequests.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "graceful", mailbox_item.reload.payload["strictness"]
    assert_equal "queued", mailbox_item.status
  end

  test "progresses mixed close requests without mailbox query explosion" do
    context = build_agent_control_context!
    process_run_a = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    process_run_b = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    task_run_a = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    task_run_b = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    subagent_session_a = create_open_owned_subagent_session!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: context[:conversation],
      executor_program: context[:executor_program],
      agent_program_version: context[:deployment]
    )
    subagent_session_b = create_open_owned_subagent_session!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: context[:conversation],
      executor_program: context[:executor_program],
      agent_program_version: context[:deployment]
    )

    [process_run_a, process_run_b, task_run_a, task_run_b, subagent_session_a, subagent_session_b].each do |resource|
      AgentControl::CreateResourceCloseRequest.call(
        resource: resource,
        request_kind: "archive",
        reason_kind: "conversation_archived",
        strictness: "graceful",
        grace_deadline_at: 2.minutes.ago,
        force_deadline_at: 1.minute.from_now
      )
    end

    queries = capture_sql_queries do
      Conversations::ProgressCloseRequests.call(
        conversation: context[:conversation],
        occurred_at: Time.current
      )
    end

    assert_operator queries.length, :<=, 25, "Expected progress close requests to stay under 25 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end

  private

  def create_open_owned_subagent_session!(installation:, workspace:, owner_conversation:, executor_program:, agent_program_version:)
    child_conversation = create_conversation_record!(
      installation: installation,
      workspace: workspace,
      parent_conversation: owner_conversation,
      kind: "fork",
      executor_program: executor_program,
      agent_program_version: agent_program_version,
      addressability: "agent_addressable"
    )

    SubagentSession.create!(
      installation: installation,
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
  end
end
