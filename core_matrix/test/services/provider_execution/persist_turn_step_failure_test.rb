require "test_helper"

class ProviderExecution::PersistTurnStepFailureTest < ActiveSupport::TestCase
  test "persists recoverable provider failures as waiting state under the shared execution lock" do
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

    result = ProviderExecution::PersistTurnStepFailure.call(
      workflow_node: workflow_node,
      request_context: request_context,
      error: error,
      provider_request_id: "provider-request-1",
      messages_count: turn_step_messages_for(workflow_run).length,
      duration_ms: 123
    )

    profiling_fact = result.profiling_fact

    assert_equal "active", workflow_run.reload.lifecycle_state
    assert_equal "waiting", workflow_run.wait_state
    assert_equal "external_dependency_blocked", workflow_run.wait_reason_kind
    assert_equal "waiting", workflow_run.turn.reload.lifecycle_state
    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal false, profiling_fact.success
    assert_equal "provider-request-1", profiling_fact.provider_request_id
    assert_equal "dev", profiling_fact.provider_handle
    assert_equal "mock-model", profiling_fact.model_ref
    assert_equal "chat_completions", profiling_fact.wire_api
    assert_equal "SimpleInference::HTTPError", profiling_fact.error_class
    assert_equal({}, profiling_fact.metadata)

    last_status_event = workflow_node.reload.workflow_node_events.order(:ordinal).last
    assert_equal "waiting", last_status_event.payload["state"]
    assert_equal "provider_overloaded", result.failure_outcome.failure_kind
    assert_equal "provider-request-1", last_status_event.payload["provider_request_id"]
    assert_equal "SimpleInference::HTTPError", last_status_event.payload["error_class"]
  end

  test "rejects stale failure replays after the turn has already been blocked" do
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

  test "persists implementation errors as terminal failures" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    request_context = build_request_context_for(workflow_run, catalog: catalog)

    result = ProviderExecution::PersistTurnStepFailure.call(
      workflow_node: workflow_node,
      request_context: request_context,
      error: StandardError.new("boom"),
      provider_request_id: "provider-request-3",
      messages_count: turn_step_messages_for(workflow_run).length,
      duration_ms: 55
    )

    assert result.failure_outcome.terminal?
    assert_equal "failed", workflow_run.reload.lifecycle_state
    assert_equal "failed", workflow_run.turn.reload.lifecycle_state
    assert_equal "failed", workflow_node.reload.lifecycle_state
    assert_equal "StandardError", result.profiling_fact.error_class
    assert_equal "boom", result.profiling_fact.error_message
  end
end
