require "test_helper"

class ExecutionRuntimeApiControlPollTest < ActionDispatch::IntegrationTest
  test "execution runtime mailbox pull delivers queued execution assignments to the authenticated execution runtime connection" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(
      context: context,
      task_payload: {
        "turn_id" => context[:turn].public_id,
        "workflow_run_id" => context[:workflow_run].public_id,
      }
    )

    post "/execution_runtime_api/mailbox/pull",
      params: { limit: 10 },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "execution_runtime_mailbox_pull", response_body.fetch("method_id")
    item = response_body.fetch("mailbox_items").fetch(0)
    payload = item.fetch("payload")

    assert_equal scenario.fetch(:mailbox_item).public_id, item.fetch("item_id")
    assert_equal "execution_assignment", item.fetch("item_type")
    assert_equal "execution_runtime", item.fetch("control_plane")
    refute item.key?("target_kind")
    refute item.key?("target_ref")
    assert_equal "agent-runtime/2026-04-01", payload.fetch("protocol_version")
    assert_equal "execution_assignment", payload.fetch("request_kind")
    assert_equal context[:workflow_run].public_id, payload.dig("task", "workflow_run_id")
    assert_equal context[:turn].public_id, payload.dig("task", "turn_id")
    assert_equal "execution_runtime", payload.dig("runtime_context", "control_plane")
    refute payload.key?("control_plane")
    assert_equal 1, item.fetch("delivery_no")
    assert_equal context[:execution_runtime_connection].public_id, scenario.fetch(:mailbox_item).reload.leased_to_execution_runtime_connection.public_id
    assert_nil scenario.fetch(:mailbox_item).reload.leased_to_agent_connection
    refute_includes response.body, %("#{context[:workflow_run].id}")
  end

  test "execution runtime mailbox pull delivers execution-runtime-plane close work to the authenticated execution runtime connection" do
    context = build_rotated_runtime_context!
    other_agent = create_agent!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: other_agent,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      control_plane: "execution_runtime",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )

    post "/execution_runtime_api/mailbox/pull",
      params: { limit: 10 },
      headers: execution_runtime_api_headers(context[:replacement_execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)

    assert_equal mailbox_item.public_id, item.fetch("item_id")
    assert_equal "execution_runtime", item.fetch("control_plane")
    refute item.key?("target_kind")
    refute item.key?("target_ref")
    assert_equal context[:execution_runtime_connection].public_id, mailbox_item.reload.leased_to_execution_runtime_connection.public_id
    assert_nil mailbox_item.leased_to_agent_connection
  end

  test "execution runtime mailbox pull delivers execution-runtime-plane close requests from the writer path without payload routing fallbacks" do
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

    post "/execution_runtime_api/mailbox/pull",
      params: { limit: 10 },
      headers: execution_runtime_api_headers(context[:replacement_execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)

    assert_equal mailbox_item.public_id, item.fetch("item_id")
    assert_equal "execution_runtime", item.fetch("control_plane")
    refute item.key?("target_kind")
    refute item.key?("target_ref")
    assert_equal "ProcessRun", item.dig("payload", "resource_type")
    assert_equal process_run.public_id, item.dig("payload", "resource_id")
    refute item.fetch("payload").key?("control_plane")
    refute item.fetch("payload").key?("execution_runtime_id")
    assert_equal context[:execution_runtime].id, mailbox_item.reload.target_execution_runtime_id
    assert_equal context[:execution_runtime_connection].public_id, mailbox_item.reload.leased_to_execution_runtime_connection.public_id
    assert_nil mailbox_item.leased_to_agent_connection
  end

  test "legacy execution runtime control poll route is removed" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/execution_runtime_api/control/poll", method: :post)
    end
  end
end
