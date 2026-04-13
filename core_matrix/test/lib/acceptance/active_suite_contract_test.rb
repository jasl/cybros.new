require "test_helper"
require Rails.root.join("../acceptance/lib/active_suite")
require Rails.root.join("../acceptance/lib/governed_validation_support")

class Acceptance::ActiveSuiteContractTest < ActiveSupport::TestCase
  FORBIDDEN_OBSOLETE_SHORTCUTS = [
    "OnboardingSessions::Issue.call",
    "ConversationDebugExports::BuildPayload.call",
    "workflow_node_keys(",
    "workflow_state_hash(",
    "wait_for_turn_workflow_terminal!",
  ].freeze

  test "active acceptance suite only references existing entrypoints" do
    Acceptance::ActiveSuite.entrypoints.each do |entrypoint|
      assert Rails.root.join("..", entrypoint).exist?, "expected active acceptance entrypoint #{entrypoint} to exist"
    end
  end

  test "every active scenario declares acceptance metadata" do
    assert_equal(
      Acceptance::ActiveSuite::ACTIVE_SCENARIOS.sort,
      Acceptance::ActiveSuite.scenario_metadata.keys.sort
    )
  end

  test "optional acceptance entrypoints expose enablement and skip metadata" do
    env_var = "ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE"

    assert_includes Acceptance::ActiveSuite.optional_entrypoints.keys,
      "acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh"

    optional_entry = Acceptance::ActiveSuite.optional_entrypoints.fetch(
      "acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh"
    )

    assert_equal env_var, optional_entry.fetch(:env_var)
    assert_equal :app_api_surface, optional_entry.fetch(:mode)
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

  test "app_api_surface scenarios avoid obsolete internal shortcuts" do
    Acceptance::ActiveSuite.scenario_metadata.each do |entrypoint, metadata|
      next unless metadata.fetch(:mode) == :app_api_surface

      scenario = Rails.root.join("..", entrypoint).read

      assert_includes scenario, "ACCEPTANCE_MODE: app_api_surface", "#{entrypoint} must declare app_api surface mode"
      assert_includes scenario, "app_api_", "#{entrypoint} must use app_api helpers"
      FORBIDDEN_OBSOLETE_SHORTCUTS.each do |shortcut|
        refute_includes scenario, shortcut, "#{entrypoint} should not use obsolete shortcut #{shortcut}"
      end
    end
  end

  test "hybrid_app_api scenarios use app_api where available and avoid obsolete shortcuts" do
    Acceptance::ActiveSuite.scenario_metadata.each do |entrypoint, metadata|
      next unless metadata.fetch(:mode) == :hybrid_app_api

      scenario = Rails.root.join("..", entrypoint).read

      assert_includes scenario, "ACCEPTANCE_MODE: hybrid_app_api", "#{entrypoint} must declare hybrid app_api mode"
      assert_includes scenario, "app_api_", "#{entrypoint} must use app_api helpers somewhere in the flow"
      FORBIDDEN_OBSOLETE_SHORTCUTS.each do |shortcut|
        refute_includes scenario, shortcut, "#{entrypoint} should not use obsolete shortcut #{shortcut}"
      end
    end
  end

  test "internal workflow scenarios explicitly declare their control-plane boundary" do
    Acceptance::ActiveSuite.scenario_metadata.each do |entrypoint, metadata|
      next unless metadata.fetch(:mode) == :internal_workflow

      scenario = Rails.root.join("..", entrypoint).read

      assert_includes scenario, "ACCEPTANCE_MODE: internal_workflow", "#{entrypoint} must declare internal workflow mode"
      assert_includes scenario, "no equivalent app_api surface", "#{entrypoint} must explain why it remains internal"
    end
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

  test "governed acceptance support builds task context with the agent definition selector snapshot" do
    context = create_workspace_context!

    task_context = GovernedValidationSupport.create_task_context!(
      workspace: context.fetch(:workspace),
      agent_definition_version: context.fetch(:agent_definition_version),
      content: "Test governed selector snapshot",
      allowed_tool_names: ["shell.exec"]
    )

    assert_equal(
      context.fetch(:agent_definition_version).public_id,
      task_context.fetch(:turn).resolved_model_selection_snapshot.fetch("agent_definition_version_id")
    )
  end
end
