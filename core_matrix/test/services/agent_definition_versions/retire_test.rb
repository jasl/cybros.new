require "test_helper"

class AgentDefinitionVersions::RetireTest < ActiveSupport::TestCase
  test "moves the agent definition version into the retired state and makes it ineligible for future scheduling" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)

    AgentDefinitionVersions::Retire.call(
      agent_definition_version: context[:agent_definition_version],
      actor: context[:user]
    )

    agent_definition_version = context[:agent_definition_version].reload
    assert agent_definition_version.retired?
    assert_equal "superseded", agent_definition_version.bootstrap_state
    refute agent_definition_version.eligible_for_scheduling?
    assert_equal "agent_definition_version_retired", agent_definition_version.unavailability_reason

    audit_log = AuditLog.find_by!(action: "agent_definition_version.retired")
    assert_equal agent_definition_version, audit_log.subject
    assert_equal context[:user], audit_log.actor
  end
end
