require_relative "../core_matrix_hosted_test_helper"
require "verification/suites/perf/profile"
require "verification/suites/perf/topology"
require "verification/suites/perf/provider_catalog_override"

class Verification::PerfProviderCatalogOverrideHostedTest < ActiveSupport::TestCase
  test "builds a stress override that lifts dev provider concurrency to the conversation count" do
    with_topology(profile_name: "stress", artifact_stamp: "2026-04-09-stress") do |profile, topology|
      override = Verification::Perf::ProviderCatalogOverride.build(
        profile: profile,
        topology: topology,
        rails_root: Rails.root,
        env: "test"
      )

      assert override.present?
      assert_equal profile.conversation_count, override.payload.dig("providers", "dev", "admission_control", "max_concurrent_requests")
      assert override.catalog.present?
      assert_equal "llm_catalog.test.yml", override.override_path.basename.to_s
      assert override.override_path.exist?
    end
  end

  test "skips catalog overrides for execution-assignment profiles" do
    with_topology(profile_name: "smoke", artifact_stamp: "2026-04-09-smoke") do |profile, topology|
      override = Verification::Perf::ProviderCatalogOverride.build(
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
      Dir.mktmpdir do |verification_root|
        profile = Verification::Perf::Profile.fetch(profile_name)
        topology = Verification::Perf::Topology.build(
          profile: profile,
          repo_root: repo_root,
          verification_root: verification_root,
          artifact_stamp: artifact_stamp
        )

        yield profile, topology
      end
    end
  end
end
