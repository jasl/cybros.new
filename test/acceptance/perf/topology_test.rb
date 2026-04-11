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
          profile: Profile.fetch("baseline_1_fenix_4_nexus"),
          repo_root: REPO_ROOT,
          acceptance_root: ACCEPTANCE_ROOT,
          artifact_stamp: "2026-04-09-baseline-1-fenix-4-nexus"
        )

        assert_equal "baseline_1_fenix_4_nexus", topology.profile_name
        assert_equal 4, topology.runtime_count
        assert_equal REPO_ROOT.join("tmp", "multi-agent-runtime-core-matrix-load", "2026-04-09-baseline-1-fenix-4-nexus"), topology.run_root
        assert_equal ACCEPTANCE_ROOT.join("artifacts", "2026-04-09-baseline-1-fenix-4-nexus"), topology.artifact_root

        slot_one = topology.runtime_slot(1)
        assert_equal "nexus-01", slot_one.label
        assert_equal "http://127.0.0.1:3201", slot_one.runtime_base_url
        assert_equal 3410, slot_one.proxy_port
        assert_equal REPO_ROOT.join("tmp", "multi-agent-runtime-core-matrix-load", "2026-04-09-baseline-1-fenix-4-nexus", "nexus-01", "home"), slot_one.home_root
        assert_equal ACCEPTANCE_ROOT.join("artifacts", "2026-04-09-baseline-1-fenix-4-nexus", "evidence", "nexus-01-events.ndjson"), slot_one.event_output_path
        assert_equal "nexus-load-2026-04-09-baseline-1-fenix-4-nexus-01", slot_one.container_name
        assert_equal "nexus-load-2026-04-09-baseline-1-fenix-4-nexus-01-proxy", slot_one.proxy_container_name

        slot_four = topology.runtime_slot(4)
        assert_equal "nexus-04", slot_four.label
        assert_equal "http://127.0.0.1:3204", slot_four.runtime_base_url
        assert_equal 3413, slot_four.proxy_port
        assert_equal "nexus-load-2026-04-09-baseline-1-fenix-4-nexus-04", slot_four.container_name
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
