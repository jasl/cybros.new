require "test_helper"

class ExecutionApiControlPollTest < ActionDispatch::IntegrationTest
  test "execution poll delivers execution-plane close work to the authenticated execution session" do
    context = build_rotated_runtime_context!
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
        "reason_kind" => "turn_interrupted",
      }
    )

    post "/execution_api/control/poll",
      params: { limit: 10 },
      headers: execution_api_headers(context[:replacement_execution_machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)

    assert_equal mailbox_item.public_id, item.fetch("item_id")
    assert_equal "execution", item.fetch("runtime_plane")
    refute item.key?("target_kind")
    refute item.key?("target_ref")
    assert_equal context[:execution_session].public_id, mailbox_item.reload.leased_to_execution_session.public_id
    assert_nil mailbox_item.leased_to_agent_session
  end

  test "execution poll delivers execution-plane close requests from the writer path without payload routing fallbacks" do
    context = build_rotated_runtime_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run,
      reason_kind: "turn_interrupted"
    ).fetch(:mailbox_item)

    post "/execution_api/control/poll",
      params: { limit: 10 },
      headers: execution_api_headers(context[:replacement_execution_machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)

    assert_equal mailbox_item.public_id, item.fetch("item_id")
    assert_equal "execution", item.fetch("runtime_plane")
    refute item.key?("target_kind")
    refute item.key?("target_ref")
    assert_equal "ProcessRun", item.dig("payload", "resource_type")
    assert_equal process_run.public_id, item.dig("payload", "resource_id")
    refute item.fetch("payload").key?("runtime_plane")
    refute item.fetch("payload").key?("execution_runtime_id")
    assert_equal context[:execution_runtime].id, mailbox_item.reload.target_execution_runtime_id
    assert_equal context[:execution_session].public_id, mailbox_item.reload.leased_to_execution_session.public_id
    assert_nil mailbox_item.leased_to_agent_session
  end
end
