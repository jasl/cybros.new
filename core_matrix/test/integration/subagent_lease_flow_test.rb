require "test_helper"

class SubagentLeaseFlowTest < ActionDispatch::IntegrationTest
  test "workflow-owned subagent runs can fan out and complete through execution leases" do
    context = build_subagent_context!
    terminal_summary = WorkflowArtifact.create!(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      artifact_key: "terminal-summary",
      artifact_kind: "subagent_terminal_summary",
      storage_mode: "inline_json",
      payload: {}
    )

    researcher = Subagents::Spawn.call(
      workflow_node: context[:workflow_node],
      requested_role_or_slot: "researcher",
      batch_key: "batch-1",
      coordination_key: "fanout-1"
    )
    critic = Subagents::Spawn.call(
      workflow_node: context[:workflow_node],
      parent_subagent_run: researcher,
      requested_role_or_slot: "critic",
      batch_key: "batch-1",
      coordination_key: "fanout-1",
      terminal_summary_artifact: terminal_summary
    )

    researcher_lease = Leases::Acquire.call(
      leased_resource: researcher,
      holder_key: "runtime-a",
      heartbeat_timeout_seconds: 30
    )
    critic_lease = Leases::Acquire.call(
      leased_resource: critic,
      holder_key: "runtime-b",
      heartbeat_timeout_seconds: 30
    )

    travel 5.seconds do
      Leases::Heartbeat.call(execution_lease: critic_lease, holder_key: "runtime-b")
      Leases::Release.call(execution_lease: researcher_lease, holder_key: "runtime-a", reason: "completed")
      Leases::Release.call(execution_lease: critic_lease, holder_key: "runtime-b", reason: "completed")
    end

    assert_equal context[:workflow_run], critic.reload.workflow_run
    assert_equal context[:workflow_node], researcher.reload.workflow_node
    assert_equal [researcher.id, critic.id], context[:workflow_node].subagent_runs.order(:id).pluck(:id)
    assert_equal %w[completed completed], ExecutionLease.order(:id).pluck(:release_reason)
  end
end
