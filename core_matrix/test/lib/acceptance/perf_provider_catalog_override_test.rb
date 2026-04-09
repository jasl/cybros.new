require "test_helper"
require Rails.root.join("../acceptance/lib/perf/profile")
require Rails.root.join("../acceptance/lib/perf/topology")
require Rails.root.join("../acceptance/lib/perf/provider_catalog_override")

class Acceptance::PerfProviderCatalogOverrideTest < ActiveSupport::TestCase
  self.uses_real_provider_catalog = true

  test "builds a stress override that lifts dev provider concurrency to the conversation count" do
    with_topology(profile_name: "stress", artifact_stamp: "2026-04-09-stress") do |profile, topology|
      override = Acceptance::Perf::ProviderCatalogOverride.build(
        profile: profile,
        topology: topology,
        rails_root: Rails.root,
        env: "test"
      )

      assert override.present?
      assert_equal profile.conversation_count, override.payload.dig("providers", "dev", "admission_control", "max_concurrent_requests")
      assert_equal profile.conversation_count, override.catalog.provider("dev").dig(:admission_control, :max_concurrent_requests)
      assert_equal 5, override.catalog.provider("dev").dig(:admission_control, :cooldown_seconds)
      assert_equal "llm_catalog.test.yml", override.override_path.basename.to_s
      assert override.override_path.exist?
    end
  end

  test "write creates the override file without requiring provider catalog loading" do
    Dir.mktmpdir do |override_dir|
      profile = Acceptance::Perf::Profile.fetch("stress")

      override = Acceptance::Perf::ProviderCatalogOverride.write(
        profile: profile,
        override_dir: override_dir,
        env: "test"
      )

      assert override.present?
      assert_nil override.catalog
      assert_equal File.join(override_dir, "llm_catalog.test.yml"), override.override_path.to_s
      assert_equal profile.conversation_count, override.payload.dig("providers", "dev", "admission_control", "max_concurrent_requests")
      assert_equal override.payload, YAML.load_file(override.override_path)
    end
  end

  test "skips catalog overrides for execution-assignment profiles" do
    with_topology(profile_name: "smoke", artifact_stamp: "2026-04-09-smoke") do |profile, topology|
      override = Acceptance::Perf::ProviderCatalogOverride.build(
        profile: profile,
        topology: topology,
        rails_root: Rails.root,
        env: "test"
      )

      assert_nil override
    end
  end

  private

  def with_topology(profile_name:, artifact_stamp:)
    Dir.mktmpdir do |repo_root|
      Dir.mktmpdir do |acceptance_root|
        profile = Acceptance::Perf::Profile.fetch(profile_name)
        topology = Acceptance::Perf::Topology.build(
          profile: profile,
          repo_root: repo_root,
          acceptance_root: acceptance_root,
          artifact_stamp: artifact_stamp
        )

        yield profile, topology
      end
    end
  end
end
