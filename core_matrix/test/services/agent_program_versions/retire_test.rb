require "test_helper"

module AgentProgramVersions
end

class AgentProgramVersions::RetireTest < ActiveSupport::TestCase
  test "moves the deployment into the retired state and makes it ineligible for future scheduling" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)

    AgentProgramVersions::Retire.call(
      deployment: context[:agent_program_version],
      actor: context[:user]
    )

    deployment = context[:agent_program_version].reload
    assert deployment.retired?
    assert_equal "superseded", deployment.bootstrap_state
    refute deployment.eligible_for_scheduling?

    audit_log = AuditLog.find_by!(action: "agent_program_version.retired")
    assert_equal deployment, audit_log.subject
    assert_equal context[:user], audit_log.actor
  end
end
