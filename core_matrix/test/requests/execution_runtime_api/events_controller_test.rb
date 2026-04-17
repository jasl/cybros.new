require "test_helper"

class ExecutionRuntimeApiEventsControllerTest < ActionDispatch::IntegrationTest
  test "events batch accepts multiple runtime events and returns per-event results" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    AgentControl::Poll.call(
      execution_runtime_connection: context[:execution_runtime_connection],
      limit: 10
    )

    post "/execution_runtime_api/events/batch",
      params: {
        events: [
          {
            method_id: "execution_started",
            protocol_message_id: "runtime-start-#{next_test_sequence}",
            mailbox_item_id: mailbox_item.public_id,
            agent_task_run_id: agent_task_run.public_id,
            logical_work_id: agent_task_run.logical_work_id,
            attempt_no: agent_task_run.attempt_no,
            expected_duration_seconds: 15,
          },
          {
            method_id: "execution_progress",
            protocol_message_id: "runtime-progress-#{next_test_sequence}",
            mailbox_item_id: mailbox_item.public_id,
            agent_task_run_id: agent_task_run.public_id,
            logical_work_id: agent_task_run.logical_work_id,
            attempt_no: agent_task_run.attempt_no,
            progress_payload: { state: "running" },
          },
        ],
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    results = response_body.fetch("results")

    assert_equal "execution_runtime_events_batch", response_body.fetch("method_id")
    assert_equal 2, results.length
    assert_equal %w[accepted accepted], results.map { |result| result.fetch("result") }
    assert results.all? { |result| result.key?("mailbox_items") }
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "running", agent_task_run.reload.lifecycle_state
  end
end
