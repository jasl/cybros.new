require "test_helper"

class RuntimeFlowTest < ActionDispatch::IntegrationTest
  test "runtime execution endpoint returns start progress and terminal reports" do
    post "/runtime/executions",
      params: runtime_assignment_payload(mode: "deterministic_tool"),
      as: :json

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal %w[execution_started execution_progress execution_complete],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal "completed", body.fetch("status")
    assert_equal "The calculator returned 4.", body.fetch("output")
  end

  test "runtime execution endpoint reports failures through handle_error" do
    post "/runtime/executions",
      params: runtime_assignment_payload(mode: "raise_error"),
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)

    assert_equal %w[execution_started execution_fail],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal "failed", body.fetch("status")
    assert_equal "runtime_error", body.fetch("error").fetch("failure_kind")
  end
end
