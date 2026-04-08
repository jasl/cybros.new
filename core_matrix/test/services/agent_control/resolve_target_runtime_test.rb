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

    assert_equal "program", result.control_plane
    assert_nil result.executor_program
    assert_equal context[:agent_session], result.delivery_endpoint
    assert result.matches?(context[:deployment])
  end

  test "routes executor-plane work by executor program instead of program hints" do
    context = build_agent_control_context!
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_executor_program: context[:executor_program],
      item_type: "resource_close_request",
      control_plane: "executor",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    result = AgentControl::ResolveTargetRuntime.call(mailbox_item: mailbox_item)

    assert_equal "executor", result.control_plane
    assert_equal context[:executor_program], result.executor_program
    assert_equal context[:executor_session], result.delivery_endpoint
    assert result.matches?(context[:executor_session])
    refute result.matches?(context[:deployment])
  end
end
