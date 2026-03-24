require "test_helper"

class ExecutionProfilingFlowTest < ActionDispatch::IntegrationTest
  test "recording execution profile facts does not create provider usage rows" do
    installation = create_installation!

    fact = ExecutionProfiling::RecordFact.call(
      installation: installation,
      fact_kind: "process_failure",
      fact_key: "sandbox_exec",
      process_run_id: 505,
      success: false,
      occurred_at: Time.utc(2026, 3, 24, 12, 15, 0),
      metadata: { "exit_code" => 1 }
    )

    assert_equal 1, ExecutionProfileFact.count
    assert_equal fact, ExecutionProfileFact.last
    assert_equal 0, UsageEvent.count
    assert_equal 0, UsageRollup.count
  end
end
