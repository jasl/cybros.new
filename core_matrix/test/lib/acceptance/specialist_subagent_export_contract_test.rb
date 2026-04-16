require "test_helper"
require Rails.root.join("../acceptance/lib/active_suite")

class Acceptance::SpecialistSubagentExportContractTest < ActiveSupport::TestCase
  test "active suite exposes the specialist subagent export scenario" do
    entrypoint = "acceptance/scenarios/specialist_subagent_export_validation.rb"

    assert_includes Acceptance::ActiveSuite.entrypoints, entrypoint
    assert_equal :hybrid_app_api, Acceptance::ActiveSuite.scenario_metadata.fetch(entrypoint).fetch(:mode)
  end

  test "specialist subagent export scenario proves tester delegation artifacts" do
    scenario = Rails.root.join("../acceptance/scenarios/specialist_subagent_export_validation.rb").read

    assert_includes scenario, "ACCEPTANCE_MODE: hybrid_app_api"
    assert_includes scenario, "\"profile_key\" => \"tester\""
    assert_includes scenario, "app_api_export_conversation!"
    assert_includes scenario, "app_api_debug_export_conversation!"
    assert_includes scenario, "\"delegation_summary\""
    assert_includes scenario, "\"subagent_connections\""
    assert_includes scenario, "workflow-mermaid.md"
  end
end
