require "test_helper"

class AgentControl::ApplySupervisionUpdateTest < ActiveSupport::TestCase
  test "partial supervision updates preserve an existing subagent observed status" do
    context = build_agent_control_context!
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      parent_conversation: context[:conversation],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      observed_status: "waiting",
      supervision_state: "waiting",
      waiting_summary: "Waiting on a provider retry",
      last_progress_at: 2.minutes.ago,
      supervision_payload: {}
    )
    agent_task_run = create_agent_task_run!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      workflow_node: context[:workflow_node],
      subagent_session: subagent_session,
      lifecycle_state: "running",
      started_at: 3.minutes.ago,
      supervision_state: "waiting",
      waiting_summary: "Waiting on a provider retry",
      last_progress_at: 2.minutes.ago,
      supervision_payload: {}
    )

    AgentControl::ApplySupervisionUpdate.call(
      agent_task_run: agent_task_run,
      payload: {
        "supervision_update" => {
          "recent_progress_summary" => "Captured the failing stack trace",
        },
      },
      occurred_at: Time.current
    )

    subagent_session.reload

    assert_equal "waiting", subagent_session.observed_status
    assert_equal "waiting", subagent_session.supervision_state
    assert_equal "Captured the failing stack trace", subagent_session.recent_progress_summary
  end

  test "child subagent task progress entries stay local to the child conversation" do
    context = build_agent_control_context!
    child_scenario = spawn_child_subagent_execution!(context:)
    agent_task_run = child_scenario.fetch(:agent_task_run)
    subagent_session = child_scenario.fetch(:subagent_session)

    AgentControl::ApplySupervisionUpdate.call(
      agent_task_run: agent_task_run,
      payload: {
        "supervision_update" => {
          "recent_progress_summary" => "Captured the failing stack trace",
        },
      },
      occurred_at: Time.current
    )

    entry = agent_task_run.reload.agent_task_progress_entries.order(:sequence).last

    assert_equal "progress_recorded", entry.entry_kind
    assert_nil entry.subagent_session
    assert_equal "Captured the failing stack trace", subagent_session.reload.recent_progress_summary
  end

  private

  def spawn_child_subagent_execution!(context:)
    promote_subagent_runtime_context!(context)

    result = SubagentSessions::Spawn.call(
      conversation: context.fetch(:conversation),
      origin_turn: context.fetch(:turn),
      content: "Investigate the failing branch",
      scope: "conversation",
      profile_key: "researcher"
    )

    {
      agent_task_run: AgentTaskRun.find_by!(public_id: result.fetch("agent_task_run_id")),
      subagent_session: SubagentSession.find_by!(public_id: result.fetch("subagent_session_id")),
    }
  end
end
