require "test_helper"
require Rails.root.join("../acceptance/lib/active_suite")

class Acceptance::WorkspaceAgentModelOverrideContractTest < ActiveSupport::TestCase
  test "active suite exposes the workspace agent model override scenario" do
    entrypoint = "acceptance/scenarios/workspace_agent_model_override_validation.rb"

    assert_includes Acceptance::ActiveSuite.entrypoints, entrypoint
    assert_equal :app_api_surface, Acceptance::ActiveSuite.scenario_metadata.fetch(entrypoint).fetch(:mode)
  end

  test "workspace agent model override scenario proves mounted selector override through app api" do
    scenario = Rails.root.join("../acceptance/scenarios/workspace_agent_model_override_validation.rb").read

    assert_includes scenario, "ACCEPTANCE_MODE: app_api_surface"
    assert_includes scenario, "app_api_patch_json"
    assert_includes scenario, "\"role:mock\""
    assert_includes scenario, "app_api_create_conversation!"
    assert_includes scenario, "app_api_debug_export_conversation!"
    assert_includes scenario, "\"resolved_model_selection_snapshot\""
  end
end
