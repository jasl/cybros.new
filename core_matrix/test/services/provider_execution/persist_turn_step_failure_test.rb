require "test_helper"

class ProviderExecution::PersistTurnStepFailureTest < ActiveSupport::TestCase
  test "persists terminal failure side effects under the shared execution lock" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
        "presence_penalty" => 0.6,
      },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    error = build_provider_http_error

    profiling_fact = ProviderExecution::PersistTurnStepFailure.call(
      workflow_node: workflow_node,
      request_context: request_context,
      error: error,
      provider_request_id: "provider-request-1",
      messages_count: turn_step_messages_for(workflow_run).length,
      duration_ms: 123
    )

    assert_equal "failed", workflow_run.reload.lifecycle_state
    assert_equal "failed", workflow_run.turn.reload.lifecycle_state
    assert_equal false, profiling_fact.success
    assert_equal "provider-request-1", profiling_fact.metadata["provider_request_id"]
    assert_equal "SimpleInference::HTTPError", profiling_fact.metadata["error_class"]

    last_status_event = workflow_node.reload.workflow_node_events.order(:ordinal).last
    assert_equal "failed", last_status_event.payload["state"]
    assert_equal "provider-request-1", last_status_event.payload["provider_request_id"]
    assert_equal "SimpleInference::HTTPError", last_status_event.payload["error_class"]
  end

  test "rejects stale failure replays after the turn already failed" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
        "presence_penalty" => 0.6,
      },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    error = build_provider_http_error

    ProviderExecution::PersistTurnStepFailure.call(
      workflow_node: workflow_node,
      request_context: request_context,
      error: error,
      provider_request_id: "provider-request-1",
      messages_count: turn_step_messages_for(workflow_run).length,
      duration_ms: 123
    )

    assert_raises(ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError) do
      ProviderExecution::PersistTurnStepFailure.call(
        workflow_node: workflow_node,
        request_context: request_context,
        error: error,
        provider_request_id: "provider-request-2",
        messages_count: turn_step_messages_for(workflow_run).length,
        duration_ms: 234
      )
    end

    assert_equal 1, workflow_node.reload.workflow_node_events.where(event_kind: "status").count
  end
end
