require "test_helper"

module AgentSnapshots
end

class AgentSnapshots::RetireTest < ActiveSupport::TestCase
  test "moves the agent_snapshot into the retired state and makes it ineligible for future scheduling" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)

    AgentSnapshots::Retire.call(
      agent_snapshot: context[:agent_snapshot],
      actor: context[:user]
    )

    agent_snapshot = context[:agent_snapshot].reload
    assert agent_snapshot.retired?
    assert_equal "superseded", agent_snapshot.bootstrap_state
    refute agent_snapshot.eligible_for_scheduling?

    audit_log = AuditLog.find_by!(action: "agent_snapshot.retired")
    assert_equal agent_snapshot, audit_log.subject
    assert_equal context[:user], audit_log.actor
  end
end
