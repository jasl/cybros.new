require "test_helper"

class LeasesAcquireTest < ActiveSupport::TestCase
  test "expires a stale lease before granting a replacement lease" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )

    first_lease = Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: "worker-1",
      heartbeat_timeout_seconds: 30
    )

    travel 31.seconds do
      replacement_lease = Leases::Acquire.call(
        leased_resource: agent_task_run,
        holder_key: "worker-2",
        heartbeat_timeout_seconds: 30
      )

      assert_equal "heartbeat_timeout", first_lease.reload.release_reason
      assert_not first_lease.active?
      assert_equal agent_task_run, replacement_lease.leased_resource
      assert_equal "worker-2", replacement_lease.holder_key
      assert replacement_lease.active?
    end
  end

  test "supports agent task runs as leased runtime resources" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )

    lease = Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:agent_snapshot].public_id,
      heartbeat_timeout_seconds: 30
    )

    assert_equal agent_task_run, lease.leased_resource
    assert_equal context[:agent_snapshot].public_id, lease.holder_key
    assert lease.active?
  end
end
