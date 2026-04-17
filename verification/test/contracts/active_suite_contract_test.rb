require_relative "../test_helper"
require "verification/active_suite"

class Verification::ActiveSuiteContractTest < ActiveSupport::TestCase
  FORBIDDEN_OBSOLETE_SHORTCUTS = [
    "OnboardingSessions::Issue.call",
    "ConversationDebugExports::BuildPayload.call",
    "workflow_node_keys(",
    "workflow_state_hash(",
    "wait_for_turn_workflow_terminal!",
  ].freeze

  test "active verification suite only references existing entrypoints" do
    Verification::ActiveSuite.entrypoints.each do |entrypoint|
      assert entrypoint_path(entrypoint).exist?, "expected active verification entrypoint #{entrypoint} to exist"
    end
  end

  test "every active scenario declares verification metadata" do
    assert_equal(
      Verification::ActiveSuite::ACTIVE_SCENARIOS.sort,
      Verification::ActiveSuite.scenario_metadata.keys.sort
    )
  end

  test "optional verification entrypoints expose enablement and skip metadata" do
    env_var = "ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE"

    assert_includes Verification::ActiveSuite.optional_entrypoints.keys,
      "verification/bin/fenix_capstone_app_api_roundtrip_validation.sh"

    optional_entry = Verification::ActiveSuite.optional_entrypoints.fetch(
      "verification/bin/fenix_capstone_app_api_roundtrip_validation.sh"
    )

    assert_equal env_var, optional_entry.fetch(:env_var)
    assert_equal :app_api_surface, optional_entry.fetch(:mode)
    assert_equal [], Verification::ActiveSuite.enabled_optional_entrypoints

    skipped = Verification::ActiveSuite.skipped_optional_entrypoints
    assert_equal 1, skipped.length
    assert_equal "verification/bin/fenix_capstone_app_api_roundtrip_validation.sh", skipped.first.fetch(:entrypoint)
    assert_equal env_var, skipped.first.fetch(:env_var)
    assert_includes skipped.first.fetch(:reason), "disabled by default"
  end

  test "active suite runner loads the shared active suite manifest" do
    script = Verification.repo_root.join("verification", "bin", "run_active_suite.sh").read

    assert_includes script, "require \"verification/active_suite\""
    assert_includes script, 'bash "${SCRIPT_DIR}/run_with_fresh_start.sh" "${entrypoint}"'
    assert_includes script, "skipped optional verification entrypoints:"
    assert_includes script, "Verification::ActiveSuite.skipped_optional_entrypoints"
  end

  test "app_api_surface scenarios avoid obsolete internal shortcuts" do
    Verification::ActiveSuite.scenario_metadata.each do |entrypoint, metadata|
      next unless metadata.fetch(:mode) == :app_api_surface

      scenario = entrypoint_path(entrypoint).read

      assert_includes scenario, "VERIFICATION_MODE: app_api_surface", "#{entrypoint} must declare app_api surface mode"
      assert_includes scenario, "app_api_", "#{entrypoint} must use app_api helpers"
      FORBIDDEN_OBSOLETE_SHORTCUTS.each do |shortcut|
        refute_includes scenario, shortcut, "#{entrypoint} should not use obsolete shortcut #{shortcut}"
      end
    end
  end

  test "hybrid_app_api scenarios use app_api where available and avoid obsolete shortcuts" do
    Verification::ActiveSuite.scenario_metadata.each do |entrypoint, metadata|
      next unless metadata.fetch(:mode) == :hybrid_app_api

      scenario = entrypoint_path(entrypoint).read

      assert_includes scenario, "VERIFICATION_MODE: hybrid_app_api", "#{entrypoint} must declare hybrid app_api mode"
      assert_includes scenario, "app_api_", "#{entrypoint} must use app_api helpers somewhere in the flow"
      FORBIDDEN_OBSOLETE_SHORTCUTS.each do |shortcut|
        refute_includes scenario, shortcut, "#{entrypoint} should not use obsolete shortcut #{shortcut}"
      end
    end
  end

  test "internal workflow scenarios explicitly declare their control-plane boundary" do
    Verification::ActiveSuite.scenario_metadata.each do |entrypoint, metadata|
      next unless metadata.fetch(:mode) == :internal_workflow

      scenario = entrypoint_path(entrypoint).read

      assert_includes scenario, "VERIFICATION_MODE: internal_workflow", "#{entrypoint} must declare internal workflow mode"
      assert_includes scenario, "no equivalent app_api surface", "#{entrypoint} must explain why it remains internal"
    end
  end

  test "operator cli scenarios explicitly declare their cli boundary" do
    Verification::ActiveSuite.scenario_metadata.each do |entrypoint, metadata|
      next unless metadata.fetch(:mode) == :operator_cli_surface

      scenario = entrypoint_path(entrypoint).read

      assert_includes scenario, "VERIFICATION_MODE: operator_cli_surface", "#{entrypoint} must declare operator cli mode"
      assert_includes scenario, "cmctl", "#{entrypoint} must exercise the operator cli"
      assert_includes scenario, "Verification::CliSupport.run!", "#{entrypoint} must use the shared cli helper"
    end
  end

  test "governed verification support uses agent definition version vocabulary" do
    support = Verification.repo_root.join("verification", "lib", "verification", "support", "governed_validation_support.rb").read
    mcp_scenario = Verification.repo_root.join("verification", "scenarios", "e2e", "governed_mcp_validation.rb").read
    tool_scenario = Verification.repo_root.join("verification", "scenarios", "e2e", "governed_tool_validation.rb").read

    assert_includes support, "agent_definition_version_id"
    refute_includes support, "capability_snapshot_id"
    refute_includes support, "capability_snapshot:"
    refute_includes mcp_scenario, ".capability_snapshot"
    refute_includes tool_scenario, ".capability_snapshot"
  end

  private

  def entrypoint_path(entrypoint)
    Verification.repo_root.join(entrypoint)
  end
end
