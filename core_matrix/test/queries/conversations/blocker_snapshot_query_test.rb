require "test_helper"

class Conversations::BlockerSnapshotQueryTest < ActiveSupport::TestCase
  test "builds one snapshot that drives work barriers, close summaries, and dependency blockers" do
    context = build_agent_control_context!
    root = context[:conversation]
    child = Conversations::CreateThread.call(parent: root)
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    create_open_owned_subagent_session!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: root,
      execution_environment: context[:execution_environment],
      agent_deployment: context[:deployment]
    )

    snapshot = Conversations::BlockerSnapshotQuery.call(conversation: root)

    assert_equal 1, snapshot.work_barrier.active_turn_count
    assert_equal 1, snapshot.work_barrier.active_workflow_count
    assert_equal 1, snapshot.work_barrier.active_agent_task_count
    assert_equal 1, snapshot.work_barrier.open_blocking_interaction_count
    assert_equal 1, snapshot.work_barrier.running_turn_command_count
    assert_equal 1, snapshot.work_barrier.running_subagent_count
    assert_equal 1, snapshot.close_summary.dig(:tail, :running_background_process_count)
    assert_equal 1, snapshot.dependency_blockers.descendant_lineage_blockers
    assert request.open?
    assert child.retained?
    refute snapshot.mainline_clear?
    assert snapshot.tail_pending?
    assert snapshot.dependency_blocked?
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
