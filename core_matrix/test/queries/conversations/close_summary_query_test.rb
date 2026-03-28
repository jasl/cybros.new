require "test_helper"

class Conversations::CloseSummaryQueryTest < ActiveSupport::TestCase
  test "reports mainline blockers, tail blockers, and dependency blockers distinctly" do
    context = build_agent_control_context!
    root = context[:conversation]
    child = Conversations::CreateThread.call(parent: root)
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    running_task = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    background_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    subagent_session = create_open_owned_subagent_session!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: root,
      execution_environment: context[:execution_environment],
      agent_deployment: context[:deployment]
    )

    summary = Conversations::CloseSummaryQuery.call(conversation: root)
    snapshot = Conversations::BlockerSnapshotQuery.call(conversation: root)

    assert_equal 1, summary.dig(:mainline, :active_turn_count)
    assert_equal 1, summary.dig(:mainline, :active_workflow_count)
    assert_equal 1, summary.dig(:mainline, :active_agent_task_count)
    assert_equal 1, summary.dig(:mainline, :open_blocking_interaction_count)
    assert_equal 1, summary.dig(:mainline, :running_turn_command_count)
    assert_equal 1, summary.dig(:mainline, :running_subagent_count)
    assert_equal 1, summary.dig(:tail, :running_background_process_count)
    assert_equal 1, summary.dig(:dependencies, :descendant_lineage_blockers)
    assert_equal snapshot.close_summary, summary
    assert request.open?
    assert running_task.running?
    assert process_run.running?
    assert background_run.running?
    assert subagent_session.last_known_status_running?
    assert child.retained?
  end

  private

  def create_open_owned_subagent_session!(installation:, workspace:, owner_conversation:, execution_environment:, agent_deployment:)
    child_conversation = create_conversation_record!(
      installation: installation,
      workspace: workspace,
      parent_conversation: owner_conversation,
      kind: "thread",
      execution_environment: execution_environment,
      agent_deployment: agent_deployment,
      addressability: "agent_addressable"
    )

    SubagentSession.create!(
      installation: installation,
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      last_known_status: "running"
    )
  end
end
