require_relative "../../test_helper"
require "verification/suites/perf/profile"
require "verification/suites/perf/topology"
require "verification/suites/perf/provider_catalog_override"

class Verification::PerfProviderCatalogOverrideTest < ActiveSupport::TestCase
  test "write creates the override file without requiring provider catalog loading" do
    Dir.mktmpdir do |override_dir|
      profile = Verification::Perf::Profile.fetch("stress")

      override = Verification::Perf::ProviderCatalogOverride.write(
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
