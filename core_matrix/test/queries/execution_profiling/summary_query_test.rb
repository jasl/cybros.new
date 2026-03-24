require "test_helper"

class ExecutionProfiling::SummaryQueryTest < ActiveSupport::TestCase
  test "aggregates execution facts by kind and key within a time window" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_installation = create_agent_installation!(installation: installation)
    binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent_installation: agent_installation
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding
    )

    ExecutionProfiling::RecordFact.call(
      installation: installation,
      user: user,
      workspace: workspace,
      fact_kind: "tool_call",
      fact_key: "shell_exec",
      count_value: 2,
      duration_ms: 120,
      success: true,
      occurred_at: Time.utc(2026, 3, 24, 12, 0, 0),
      metadata: { "tool" => "shell_exec" }
    )
    ExecutionProfiling::RecordFact.call(
      installation: installation,
      user: user,
      workspace: workspace,
      fact_kind: "tool_call",
      fact_key: "shell_exec",
      count_value: 1,
      duration_ms: 80,
      success: false,
      occurred_at: Time.utc(2026, 3, 24, 12, 5, 0),
      metadata: { "tool" => "shell_exec" }
    )
    ExecutionProfiling::RecordFact.call(
      installation: installation,
      user: user,
      workspace: workspace,
      fact_kind: "approval_wait",
      fact_key: "publish_gate",
      duration_ms: 3000,
      occurred_at: Time.utc(2026, 3, 24, 12, 10, 0),
      metadata: { "request_type" => "ApprovalRequest" }
    )
    ExecutionProfiling::RecordFact.call(
      installation: installation,
      user: user,
      workspace: workspace,
      fact_kind: "tool_call",
      fact_key: "shell_exec",
      count_value: 10,
      duration_ms: 500,
      success: true,
      occurred_at: Time.utc(2026, 3, 24, 13, 0, 0),
      metadata: { "tool" => "shell_exec" }
    )

    result = ExecutionProfiling::SummaryQuery.call(
      installation: installation,
      started_at: Time.utc(2026, 3, 24, 11, 55, 0),
      ended_at: Time.utc(2026, 3, 24, 12, 59, 59)
    )

    shell_exec = result.find { |entry| entry.fact_kind == "tool_call" && entry.fact_key == "shell_exec" }
    approval_wait = result.find { |entry| entry.fact_kind == "approval_wait" && entry.fact_key == "publish_gate" }

    assert_equal 2, shell_exec.event_count
    assert_equal 3, shell_exec.total_count_value
    assert_equal 200, shell_exec.total_duration_ms
    assert_equal 1, shell_exec.success_count
    assert_equal 1, shell_exec.failure_count
    assert_equal Time.utc(2026, 3, 24, 12, 5, 0), shell_exec.last_occurred_at

    assert_equal 1, approval_wait.event_count
    assert_equal 0, approval_wait.total_count_value
    assert_equal 3000, approval_wait.total_duration_ms
    assert_equal 0, approval_wait.success_count
    assert_equal 0, approval_wait.failure_count
  end
end
