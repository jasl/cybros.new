require "test_helper"

class ExecutionProfiling::RecordFactTest < ActiveSupport::TestCase
  test "records execution profile facts through an explicit service boundary" do
    context = build_agent_control_context!

    fact = ExecutionProfiling::RecordFact.call(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      workflow_run: context[:workflow_run],
      conversation_id: context[:conversation].id,
      turn_id: context[:turn].id,
      workflow_node_key: "approval-step",
      human_interaction_request_id: 404,
      fact_kind: "approval_wait",
      fact_key: "human_gate",
      duration_ms: 45_000,
      occurred_at: Time.utc(2026, 3, 24, 12, 10, 0),
      metadata: { "source" => "manual" }
    )

    assert_equal context[:installation], fact.installation
    assert_equal context[:user], fact.user
    assert_equal context[:workspace], fact.workspace
    assert_equal context[:agent], fact.agent
    assert_equal context[:execution_runtime], fact.execution_runtime
    assert_equal context[:workflow_run], fact.workflow_run
    assert fact.approval_wait?
    assert_equal 45_000, fact.duration_ms
  end
end
