require "minitest/autorun"
require "pathname"

require_relative "../../../acceptance/lib/perf/runtime_slot"

module Acceptance
  module Perf
    class RuntimeSlotTest < Minitest::Test
      REPO_ROOT = Pathname.new(File.expand_path("../../..", __dir__))
      ACCEPTANCE_ROOT = REPO_ROOT.join("acceptance")

      def test_runtime_slots_derive_unique_ports_storage_and_event_paths
        slot_one = build_slot(index: 1)
        slot_two = build_slot(index: 2)

        assert_equal "http://127.0.0.1:3201", slot_one.runtime_base_url
        assert_equal "http://127.0.0.1:3202", slot_two.runtime_base_url
        assert_equal 3410, slot_one.proxy_port
        assert_equal 3411, slot_two.proxy_port

        assert_equal REPO_ROOT.join("tmp", "multi-agent-runtime-core-matrix-load", "2026-04-09-baseline-1-fenix-4-nexus", "nexus-01", "home"), slot_one.home_root
        assert_equal REPO_ROOT.join("tmp", "multi-agent-runtime-core-matrix-load", "2026-04-09-baseline-1-fenix-4-nexus", "nexus-02", "home"), slot_two.home_root
        assert_equal ACCEPTANCE_ROOT.join("artifacts", "2026-04-09-baseline-1-fenix-4-nexus", "evidence", "nexus-01-events.ndjson"), slot_one.event_output_path
        assert_equal ACCEPTANCE_ROOT.join("artifacts", "2026-04-09-baseline-1-fenix-4-nexus", "evidence", "nexus-02-events.ndjson"), slot_two.event_output_path

        refute_equal slot_one.docker_workspace_root, slot_two.docker_workspace_root
        refute_equal slot_one.docker_storage_volume, slot_two.docker_storage_volume
        refute_equal slot_one.docker_proxy_routes_volume, slot_two.docker_proxy_routes_volume
      end

      def test_slot_can_render_nexus_activation_env
        slot = build_slot(index: 3)
        env = slot.nexus_activation_env

        assert_equal "http://127.0.0.1:3203", env.fetch("NEXUS_RUNTIME_BASE_URL")
        assert_equal "nexus-load-2026-04-09-baseline-1-fenix-4-nexus-03", env.fetch("NEXUS_DOCKER_CONTAINER")
        assert_equal "nexus-load-2026-04-09-baseline-1-fenix-4-nexus-03-proxy", env.fetch("NEXUS_DOCKER_PROXY_CONTAINER")
        assert_equal "3412", env.fetch("NEXUS_DOCKER_PROXY_PORT")
        assert_equal REPO_ROOT.join("tmp", "multi-agent-runtime-core-matrix-load", "2026-04-09-baseline-1-fenix-4-nexus", "nexus-03", "home").to_s, env.fetch("NEXUS_HOME_ROOT")
        assert_equal ACCEPTANCE_ROOT.join("artifacts", "2026-04-09-baseline-1-fenix-4-nexus", "evidence", "nexus-03-events.ndjson").to_s, env.fetch("CYBROS_PERF_EVENTS_PATH")
        assert_equal "nexus-03", env.fetch("CYBROS_PERF_INSTANCE_LABEL")
        assert_equal "nexus-load-2026-04-09-baseline-1-fenix-4-nexus-03-storage", env.fetch("NEXUS_DOCKER_STORAGE_VOLUME")
        assert_equal "nexus-load-2026-04-09-baseline-1-fenix-4-nexus-03-proxy-routes", env.fetch("NEXUS_DOCKER_PROXY_ROUTES_VOLUME")
      end

      private

      def build_slot(index:)
        RuntimeSlot.build(
          index: index,
          run_slug: "2026-04-09-baseline-1-fenix-4-nexus",
          repo_root: REPO_ROOT,
          acceptance_root: ACCEPTANCE_ROOT,
          artifact_stamp: "2026-04-09-baseline-1-fenix-4-nexus"
        )
      end
    end
  end
end
