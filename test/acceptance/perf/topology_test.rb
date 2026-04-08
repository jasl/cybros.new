require "minitest/autorun"
require "pathname"

require_relative "../../../acceptance/lib/perf/profile"
require_relative "../../../acceptance/lib/perf/topology"

module Acceptance
  module Perf
    class TopologyTest < Minitest::Test
      REPO_ROOT = Pathname.new(File.expand_path("../../..", __dir__))
      ACCEPTANCE_ROOT = REPO_ROOT.join("acceptance")

      def test_topology_derives_deterministic_paths_ports_and_container_names
        topology = Topology.build(
          profile: Profile.fetch("target_8_fenix"),
          repo_root: REPO_ROOT,
          acceptance_root: ACCEPTANCE_ROOT,
          artifact_stamp: "2026-04-09-target-8-fenix"
        )

        assert_equal "target_8_fenix", topology.profile_name
        assert_equal 8, topology.runtime_count
        assert_equal REPO_ROOT.join("tmp", "multi-fenix-core-matrix-load", "2026-04-09-target-8-fenix"), topology.run_root
        assert_equal ACCEPTANCE_ROOT.join("artifacts", "2026-04-09-target-8-fenix"), topology.artifact_root

        slot_one = topology.runtime_slot(1)
        assert_equal "fenix-01", slot_one.label
        assert_equal "http://127.0.0.1:3101", slot_one.runtime_base_url
        assert_equal 3310, slot_one.proxy_port
        assert_equal REPO_ROOT.join("tmp", "multi-fenix-core-matrix-load", "2026-04-09-target-8-fenix", "fenix-01", "home"), slot_one.home_root
        assert_equal ACCEPTANCE_ROOT.join("artifacts", "2026-04-09-target-8-fenix", "evidence", "fenix-01-events.ndjson"), slot_one.event_output_path
        assert_equal "fenix-load-2026-04-09-target-8-fenix-01", slot_one.container_name
        assert_equal "fenix-load-2026-04-09-target-8-fenix-01-proxy", slot_one.proxy_container_name

        slot_eight = topology.runtime_slot(8)
        assert_equal "fenix-08", slot_eight.label
        assert_equal "http://127.0.0.1:3108", slot_eight.runtime_base_url
        assert_equal 3317, slot_eight.proxy_port
        assert_equal "fenix-load-2026-04-09-target-8-fenix-08", slot_eight.container_name
      end

      def test_runtime_slot_lookup_rejects_out_of_range_indices
        topology = Topology.build(
          profile: Profile.fetch("smoke"),
          repo_root: REPO_ROOT,
          acceptance_root: ACCEPTANCE_ROOT,
          artifact_stamp: "2026-04-09-smoke"
        )

        error = assert_raises(IndexError) do
          topology.runtime_slot(0)
        end

        assert_match(/runtime slot/i, error.message)
      end
    end
  end
end
