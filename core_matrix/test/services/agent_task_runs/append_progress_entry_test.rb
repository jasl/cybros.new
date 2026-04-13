require "test_helper"

class AgentTaskRuns::AppendProgressEntryTest < ActiveSupport::TestCase
  test "appends progress entries in order and updates task rollups" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "implementation",
      last_progress_at: 10.minutes.ago,
      supervision_payload: {}
    )
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_connection = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      user: child_conversation.user,
      workspace: child_conversation.workspace,
      agent: child_conversation.agent,
      scope: "conversation",
      profile_key: "worker",
      depth: 0
    )

    first_entry = AgentTaskRuns::AppendProgressEntry.call(
      agent_task_run: agent_task_run,
      entry_kind: "progress_recorded",
      summary: "Reviewed the task wiring",
      details_payload: {},
      occurred_at: 2.minutes.ago
    )
    second_entry = AgentTaskRuns::AppendProgressEntry.call(
      agent_task_run: agent_task_run,
      subagent_connection: subagent_connection,
      entry_kind: "progress_recorded",
      summary: "Delegated the next slice to a child worker",
      details_payload: { "delegated" => true },
      occurred_at: Time.current
    )

    assert_equal 1, first_entry.sequence
    assert_equal 2, second_entry.sequence
    assert_equal subagent_connection, second_entry.subagent_connection

    agent_task_run.reload
    assert_equal "Delegated the next slice to a child worker", agent_task_run.recent_progress_summary
    assert_in_delta Time.current.to_f, agent_task_run.last_progress_at.to_f, 2
  end

  test "increments supervision sequence across stale task handles" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "implementation",
      last_progress_at: 10.minutes.ago,
      supervision_payload: {}
    )

    first_handle = AgentTaskRun.find(agent_task_run.id)
    second_handle = AgentTaskRun.find(agent_task_run.id)

    AgentTaskRuns::AppendProgressEntry.call(
      agent_task_run: first_handle,
      entry_kind: "progress_recorded",
      summary: "Finished the first semantic update",
      details_payload: {},
      occurred_at: 2.minutes.ago
    )
    AgentTaskRuns::AppendProgressEntry.call(
      agent_task_run: second_handle,
      entry_kind: "progress_recorded",
      summary: "Finished the second semantic update",
      details_payload: {},
      occurred_at: Time.current
    )

    agent_task_run.reload
    assert_equal [1, 2], agent_task_run.agent_task_progress_entries.order(:sequence).pluck(:sequence)
    assert_equal 2, agent_task_run.supervision_sequence
  end
end
