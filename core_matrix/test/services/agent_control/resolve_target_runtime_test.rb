require "test_helper"

class AgentControl::ResolveTargetRuntimeTest < ActiveSupport::TestCase
  test "routes program-plane work to the explicitly targeted agent session" do
    context = build_agent_control_context!
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      target_agent_program_version: context[:deployment]
    )

    result = AgentControl::ResolveTargetRuntime.call(mailbox_item: mailbox_item)

    assert_equal "program", result.runtime_plane
    assert_nil result.execution_runtime
    assert_equal context[:agent_session], result.delivery_endpoint
    assert result.matches?(context[:deployment])
  end

  test "routes execution-plane work by execution runtime instead of program hints" do
    context = build_agent_control_context!
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      runtime_plane: "execution",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    result = AgentControl::ResolveTargetRuntime.call(mailbox_item: mailbox_item)

    assert_equal "execution", result.runtime_plane
    assert_equal context[:execution_runtime], result.execution_runtime
    assert_equal context[:execution_session], result.delivery_endpoint
    assert result.matches?(context[:deployment])
  end
end
