require "test_helper"

class AgentControl::ReportDispatchTest < ActiveSupport::TestCase
  test "routes execution, runtime-resource, close, agent, and health reports to the correct handler" do
    context = build_agent_control_context!

    assert_instance_of AgentControl::HandleExecutionReport, AgentControl::ReportDispatch.call(
      agent_snapshot: context[:agent_snapshot],
      method_id: "execution_progress",
      payload: {}
    )
    assert_instance_of AgentControl::HandleRuntimeResourceReport, AgentControl::ReportDispatch.call(
      agent_snapshot: context[:agent_snapshot],
      method_id: "process_output",
      payload: {}
    )
    assert_instance_of AgentControl::HandleCloseReport, AgentControl::ReportDispatch.call(
      agent_snapshot: context[:agent_snapshot],
      method_id: "resource_closed",
      payload: {}
    )
    assert_instance_of AgentControl::HandleAgentReport, AgentControl::ReportDispatch.call(
      agent_snapshot: context[:agent_snapshot],
      method_id: "agent_completed",
      payload: {}
    )
    assert_instance_of AgentControl::HandleHealthReport, AgentControl::ReportDispatch.call(
      agent_snapshot: context[:agent_snapshot],
      method_id: "agent_health_report",
      payload: {}
    )

    error = assert_raises(ArgumentError) do
      AgentControl::ReportDispatch.call(
        agent_snapshot: context[:agent_snapshot],
        method_id: "unknown_report",
        payload: {}
      )
    end

    assert_includes error.message, "unknown control report"
  end
end
