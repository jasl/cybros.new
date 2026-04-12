require "test_helper"
require Rails.root.join("../acceptance/lib/active_suite")

class Acceptance::ActiveSuiteContractTest < ActiveSupport::TestCase
  test "active acceptance suite only references existing entrypoints" do
    Acceptance::ActiveSuite.entrypoints.each do |entrypoint|
      assert Rails.root.join("..", entrypoint).exist?, "expected active acceptance entrypoint #{entrypoint} to exist"
    end
  end

  test "optional acceptance entrypoints expose enablement and skip metadata" do
    env_var = "ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE"

    assert_includes Acceptance::ActiveSuite.optional_entrypoints.keys,
      "acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh"

    optional_entry = Acceptance::ActiveSuite.optional_entrypoints.fetch(
      "acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh"
    )

    assert_equal env_var, optional_entry.fetch(:env_var)
    assert_equal [], Acceptance::ActiveSuite.enabled_optional_entrypoints

    skipped = Acceptance::ActiveSuite.skipped_optional_entrypoints
    assert_equal 1, skipped.length
    assert_equal "acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh", skipped.first.fetch(:entrypoint)
    assert_equal env_var, skipped.first.fetch(:env_var)
    assert_includes skipped.first.fetch(:reason), "disabled by default"
  end

  test "active suite runner loads the shared active suite manifest" do
    script = Rails.root.join("../acceptance/bin/run_active_suite.sh").read

    assert_includes script, 'require_relative "acceptance/lib/active_suite"'
    assert_includes script, 'bash "${SCRIPT_DIR}/run_with_fresh_start.sh" "${entrypoint}"'
    assert_includes script, "skipped optional acceptance entrypoints:"
    assert_includes script, "Acceptance::ActiveSuite.skipped_optional_entrypoints"
  end

  test "governed acceptance support uses agent definition version vocabulary" do
    support = Rails.root.join("../acceptance/lib/governed_validation_support.rb").read
    mcp_scenario = Rails.root.join("../acceptance/scenarios/governed_mcp_validation.rb").read
    tool_scenario = Rails.root.join("../acceptance/scenarios/governed_tool_validation.rb").read

    assert_includes support, "agent_definition_version_id"
    refute_includes support, "capability_snapshot_id"
    refute_includes support, "capability_snapshot:"
    refute_includes mcp_scenario, ".capability_snapshot"
    refute_includes tool_scenario, ".capability_snapshot"
  end
end
