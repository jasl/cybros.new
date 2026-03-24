require "test_helper"

class ExecutionLeaseTest < ActiveSupport::TestCase
  test "enforces one active lease per runtime resource and tracks heartbeat freshness" do
    context = build_subagent_context!
    subagent_run = SubagentRun.create!(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      depth: 0,
      requested_role_or_slot: "researcher",
      metadata: {}
    )

    lease = ExecutionLease.new(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      leased_resource: subagent_run,
      holder_key: "worker-1",
      heartbeat_timeout_seconds: 30,
      acquired_at: Time.current,
      last_heartbeat_at: Time.current,
      metadata: {}
    )

    assert lease.valid?
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
