require "test_helper"

class CapabilitySnapshotTest < ActiveSupport::TestCase
  test "versions snapshots and treats them as immutable" do
    deployment = create_agent_deployment!
    snapshot = create_capability_snapshot!(agent_deployment: deployment, version: 1)
    create_capability_snapshot!(agent_deployment: deployment, version: 2)

    assert_equal [1, 2], deployment.capability_snapshots.order(:version).pluck(:version)

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      snapshot.update!(default_config_snapshot: { "mode" => "changed" })
    end
  end
end
