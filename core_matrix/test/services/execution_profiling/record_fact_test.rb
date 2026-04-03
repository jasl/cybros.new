require "test_helper"

class ExecutionProfiling::RecordFactTest < ActiveSupport::TestCase
  test "records execution profile facts through an explicit service boundary" do
    installation = create_installation!
    user = create_user!(installation: installation)
    binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: create_agent_program!(installation: installation)
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: binding
    )

    fact = ExecutionProfiling::RecordFact.call(
      installation: installation,
      user: user,
      workspace: workspace,
      conversation_id: 101,
      turn_id: 202,
      workflow_node_key: "approval-step",
      human_interaction_request_id: 404,
      fact_kind: "approval_wait",
      fact_key: "human_gate",
      duration_ms: 45_000,
      occurred_at: Time.utc(2026, 3, 24, 12, 10, 0),
      metadata: { "source" => "manual" }
    )

    assert_equal installation, fact.installation
    assert_equal user, fact.user
    assert_equal workspace, fact.workspace
    assert fact.approval_wait?
    assert_equal 45_000, fact.duration_ms
  end
end
