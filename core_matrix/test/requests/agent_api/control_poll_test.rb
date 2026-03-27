require "test_helper"

class AgentApiControlPollTest < ActionDispatch::IntegrationTest
  test "poll returns queued mailbox items using the shared envelope and leases them to the authenticated deployment" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(
      context: context,
      task_payload: {
        "turn_id" => context[:turn].public_id,
        "workflow_run_id" => context[:workflow_run].public_id,
      }
    )

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)

    assert_equal scenario.fetch(:mailbox_item).public_id, item.fetch("item_id")
    assert_equal "execution_assignment", item.fetch("item_type")
    assert_equal "agent", item.fetch("runtime_plane")
    assert_equal context[:agent_installation].public_id, item.fetch("target_ref")
    assert_equal context[:workflow_run].public_id, item.dig("payload", "workflow_run_id")
    refute item.fetch("payload").key?("runtime_plane")
    assert_equal 1, item.fetch("delivery_no")
    refute_includes response.body, %("#{context[:workflow_run].id}")
  end

  test "poll delivers environment-plane close work to the rotated deployment on the same execution environment" do
    context = build_rotated_runtime_context!
    other_agent_installation = create_agent_installation!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_installation: other_agent_installation,
      target_execution_environment: context[:execution_environment],
      item_type: "resource_close_request",
      runtime_plane: "environment",
      target_kind: "agent_installation",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:replacement_machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)

    assert_equal mailbox_item.public_id, item.fetch("item_id")
    assert_equal "environment", item.fetch("runtime_plane")
    assert_equal context[:execution_environment].public_id, item.fetch("target_ref")
    assert_equal context[:replacement_deployment].public_id, mailbox_item.reload.leased_to_agent_deployment.public_id
  end

  test "poll delivers environment-plane close requests from the writer path without routing payload fallback" do
    context = build_rotated_runtime_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run,
      reason_kind: "turn_interrupted"
    ).fetch(:mailbox_item)

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:replacement_machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)

    assert_equal mailbox_item.public_id, item.fetch("item_id")
    assert_equal "environment", item.fetch("runtime_plane")
    assert_equal context[:execution_environment].public_id, item.fetch("target_ref")
    assert_equal "ProcessRun", item.dig("payload", "resource_type")
    assert_equal process_run.public_id, item.dig("payload", "resource_id")
    refute item.fetch("payload").key?("runtime_plane")
    refute item.fetch("payload").key?("execution_environment_id")
    assert_equal context[:execution_environment].id, mailbox_item.reload.target_execution_environment_id
    assert_equal context[:replacement_deployment].public_id, mailbox_item.reload.leased_to_agent_deployment.public_id
  end
end
