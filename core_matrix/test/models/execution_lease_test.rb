require "test_helper"

class ExecutionLeaseTest < ActiveSupport::TestCase
  test "accepts subagent connections as leasable runtime resources and tracks heartbeat freshness" do
    context = build_subagent_context!
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: context[:conversation],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_connection = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      user: child_conversation.user,
      workspace: child_conversation.workspace,
      agent: child_conversation.agent,
      origin_turn: context[:turn],
      scope: "turn",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )

    lease = ExecutionLease.new(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      leased_resource: subagent_connection,
      holder_key: "worker-1",
      heartbeat_timeout_seconds: 30,
      acquired_at: Time.current,
      last_heartbeat_at: Time.current,
      metadata: {}
    )

    assert lease.valid?
    assert_equal "open", subagent_connection.derived_close_status
    lease.save!
    assert lease.active?

    duplicate = lease.dup
    duplicate.holder_key = "worker-2"

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:leased_resource], "already has an active execution lease"

    travel 31.seconds do
      assert lease.reload.stale?
    end

    lease.update!(released_at: Time.current, release_reason: "completed")
    assert_not lease.reload.active?
  end
end
