require "test_helper"

class LeasesReleaseTest < ActiveSupport::TestCase
  test "releases an active lease and records the release reason" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    lease = Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: "worker-1",
      heartbeat_timeout_seconds: 30
    )

    travel 5.seconds do
      released = Leases::Release.call(
        execution_lease: lease,
        holder_key: "worker-1",
        reason: "completed"
      )

      assert_equal "completed", released.release_reason
      assert_not released.active?
      assert_in_delta Time.current.to_f, released.released_at.to_f, 1.0
    end

    error = assert_raises ArgumentError do
      Leases::Release.call(
        execution_lease: lease.reload,
        holder_key: "worker-1",
        reason: "completed"
      )
    end

    assert_match "active lease", error.message
  end
end
