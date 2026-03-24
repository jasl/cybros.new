require "test_helper"

class LeasesAcquireTest < ActiveSupport::TestCase
  test "expires a stale lease before granting a replacement lease" do
    context = build_subagent_context!
    subagent_run = Subagents::Spawn.call(
      workflow_node: context[:workflow_node],
      requested_role_or_slot: "researcher"
    )

    first_lease = Leases::Acquire.call(
      leased_resource: subagent_run,
      holder_key: "worker-1",
      heartbeat_timeout_seconds: 30
    )

    travel 31.seconds do
      replacement_lease = Leases::Acquire.call(
        leased_resource: subagent_run,
        holder_key: "worker-2",
        heartbeat_timeout_seconds: 30
      )

      assert_equal "heartbeat_timeout", first_lease.reload.release_reason
      assert_not first_lease.active?
      assert_equal subagent_run, replacement_lease.leased_resource
      assert_equal "worker-2", replacement_lease.holder_key
      assert replacement_lease.active?
    end
  end
end
