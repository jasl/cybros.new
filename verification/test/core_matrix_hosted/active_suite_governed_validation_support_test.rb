require_relative "../core_matrix_hosted_test_helper"
require "verification/support/governed_validation_support"

class Verification::ActiveSuiteGovernedValidationSupportTest < ActiveSupport::TestCase
  test "governed verification support builds task context with the agent definition selector snapshot" do
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
