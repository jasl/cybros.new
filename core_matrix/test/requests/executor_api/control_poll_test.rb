require "test_helper"

class ExecutorApiControlPollTest < ActionDispatch::IntegrationTest
  test "executor poll delivers executor-plane close work to the authenticated executor session" do
    context = build_rotated_runtime_context!
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
        "reason_kind" => "turn_interrupted",
      }
    )

    post "/executor_api/control/poll",
      params: { limit: 10 },
      headers: executor_api_headers(context[:replacement_executor_machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)

    assert_equal mailbox_item.public_id, item.fetch("item_id")
    assert_equal "executor", item.fetch("control_plane")
    refute item.key?("target_kind")
    refute item.key?("target_ref")
    assert_equal context[:executor_session].public_id, mailbox_item.reload.leased_to_executor_session.public_id
    assert_nil mailbox_item.leased_to_agent_session
  end

  test "executor poll delivers executor-plane close requests from the writer path without payload routing fallbacks" do
    context = build_rotated_runtime_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run,
      reason_kind: "turn_interrupted"
    ).fetch(:mailbox_item)

    post "/executor_api/control/poll",
      params: { limit: 10 },
      headers: executor_api_headers(context[:replacement_executor_machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)

    assert_equal mailbox_item.public_id, item.fetch("item_id")
    assert_equal "executor", item.fetch("control_plane")
    refute item.key?("target_kind")
    refute item.key?("target_ref")
    assert_equal "ProcessRun", item.dig("payload", "resource_type")
    assert_equal process_run.public_id, item.dig("payload", "resource_id")
    refute item.fetch("payload").key?("control_plane")
    refute item.fetch("payload").key?("executor_program_id")
    assert_equal context[:executor_program].id, mailbox_item.reload.target_executor_program_id
    assert_equal context[:executor_session].public_id, mailbox_item.reload.leased_to_executor_session.public_id
    assert_nil mailbox_item.leased_to_agent_session
  end
end
