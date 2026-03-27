require "test_helper"

module AgentDeployments
end

class AgentDeployments::RetireTest < ActiveSupport::TestCase
  test "moves the deployment into the retired state and makes it ineligible for future scheduling" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)

    AgentDeployments::Retire.call(
      deployment: context[:agent_deployment],
      actor: context[:user]
    )

    deployment = context[:agent_deployment].reload
    assert deployment.retired?
    assert deployment.superseded?
    refute deployment.eligible_for_scheduling?

    audit_log = AuditLog.find_by!(action: "agent_deployment.retired")
    assert_equal deployment, audit_log.subject
    assert_equal context[:user], audit_log.actor
  end
end
