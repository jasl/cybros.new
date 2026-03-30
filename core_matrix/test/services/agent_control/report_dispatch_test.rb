require "test_helper"

class AgentControl::ReportDispatchTest < ActiveSupport::TestCase
  test "routes execution, runtime-resource, close, and health reports to the correct handler" do
    context = build_agent_control_context!

    assert_instance_of AgentControl::HandleExecutionReport, AgentControl::ReportDispatch.call(
      deployment: context[:deployment],
      method_id: "execution_progress",
      payload: {}
    )
    assert_instance_of AgentControl::HandleRuntimeResourceReport, AgentControl::ReportDispatch.call(
      deployment: context[:deployment],
      method_id: "process_output",
      payload: {}
    )
    assert_instance_of AgentControl::HandleCloseReport, AgentControl::ReportDispatch.call(
      deployment: context[:deployment],
      method_id: "resource_closed",
      payload: {}
    )
    assert_instance_of AgentControl::HandleHealthReport, AgentControl::ReportDispatch.call(
      deployment: context[:deployment],
      method_id: "deployment_health_report",
      payload: {}
    )

    error = assert_raises(ArgumentError) do
      AgentControl::ReportDispatch.call(
        deployment: context[:deployment],
        method_id: "unknown_report",
        payload: {}
      )
    end

    assert_includes error.message, "unknown control report"
  end
end
