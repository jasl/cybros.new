require "test_helper"

class LeasesHeartbeatTest < ActiveSupport::TestCase
  test "refreshes a matching lease heartbeat and rejects stale heartbeats" do
    context = build_subagent_context!
    subagent_run = Subagents::Spawn.call(
      workflow_node: context[:workflow_node],
      requested_role_or_slot: "researcher"
    )
    lease = Leases::Acquire.call(
      leased_resource: subagent_run,
      holder_key: "worker-1",
      heartbeat_timeout_seconds: 30
    )

    travel 10.seconds do
      refreshed = Leases::Heartbeat.call(
        execution_lease: lease,
        holder_key: "worker-1"
      )

      assert_in_delta Time.current.to_f, refreshed.last_heartbeat_at.to_f, 1.0
    end

    travel 41.seconds do
      error = assert_raises Leases::Heartbeat::StaleLeaseError do
        Leases::Heartbeat.call(
          execution_lease: lease.reload,
          holder_key: "worker-1"
        )
      end

      assert_match "stale", error.message
      assert_equal "heartbeat_timeout", lease.reload.release_reason
    end
  end
end
