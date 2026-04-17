require "test_helper"

class ExecutionRuntimeApiMailboxControllerTest < ActionDispatch::IntegrationTest
  test "mailbox pull leases queued execution-runtime work" do
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
    item = response_body.fetch("mailbox_items").fetch(0)
    payload = item.fetch("payload")

    assert_equal "execution_runtime_mailbox_pull", response_body.fetch("method_id")
    assert_equal scenario.fetch(:mailbox_item).public_id, item.fetch("item_id")
    assert_equal "execution_assignment", item.fetch("item_type")
    assert_equal "execution_runtime", item.fetch("control_plane")
    assert_equal "execution_assignment", payload.fetch("request_kind")
    assert_equal context[:execution_runtime_connection].public_id, scenario.fetch(:mailbox_item).reload.leased_to_execution_runtime_connection.public_id
  end
end
