require "test_helper"

class ProviderExecution::PersistTurnStepSuccessTest < ActiveSupport::TestCase
  test "persists terminal success side effects under the shared execution lock" do
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
    provider_result = build_provider_chat_result

    result = ProviderExecution::PersistTurnStepSuccess.call(
      workflow_node: workflow_node,
      request_context: request_context,
      provider_result: provider_result,
      provider_request_id: "provider-request-1",
      messages_count: turn_step_messages_for(workflow_run).length,
      duration_ms: 123
    )

    assert_equal "completed", result.workflow_run.reload.lifecycle_state
    assert_equal "completed", result.output_message.turn.reload.lifecycle_state
    assert_equal "Direct provider result", result.output_message.content
    assert_equal workflow_run.turn.selected_input_message, result.output_message.source_input_message
    assert_equal true, result.usage_event.success
    assert_equal 12, result.usage_event.input_tokens
    assert_equal 8, result.usage_event.output_tokens
    assert_equal true, result.execution_profile_fact.success
    assert_equal "provider-request-1", result.execution_profile_fact.metadata["provider_request_id"]
    assert_equal 20, result.execution_profile_fact.metadata.dig("usage_evaluation", "total_tokens")
    assert_equal false, result.execution_profile_fact.metadata.dig("usage_evaluation", "threshold_crossed")

    last_status_event = workflow_node.reload.workflow_node_events.order(:ordinal).last
    assert_equal "completed", last_status_event.payload["state"]
    assert_equal result.output_message.public_id, last_status_event.payload["output_message_id"]
    assert_equal "provider-request-1", last_status_event.payload["provider_request_id"]
  end

  test "rejects stale completion replays after the turn already completed" do
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
    provider_result = build_provider_chat_result

    ProviderExecution::PersistTurnStepSuccess.call(
      workflow_node: workflow_node,
      request_context: request_context,
      provider_result: provider_result,
      provider_request_id: "provider-request-1",
      messages_count: turn_step_messages_for(workflow_run).length,
      duration_ms: 123
    )

    assert_raises(ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError) do
      ProviderExecution::PersistTurnStepSuccess.call(
        workflow_node: workflow_node,
        request_context: request_context,
        provider_result: provider_result,
        provider_request_id: "provider-request-2",
        messages_count: turn_step_messages_for(workflow_run).length,
        duration_ms: 234
      )
    end

    assert_equal 1, workflow_run.turn.reload.messages.where(slot: "output").count
    assert_equal 1, UsageEvent.count
    assert_equal 1, workflow_node.reload.workflow_node_events.where(event_kind: "status").count
  end

  test "marks the usage evaluation threshold crossed when provider totals exceed the advisory hint" do
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
    provider_result = build_provider_chat_result(
      prompt_tokens: 35,
      completion_tokens: 20,
      total_tokens: 55
    )

    result = ProviderExecution::PersistTurnStepSuccess.call(
      workflow_node: workflow_node,
      request_context: request_context,
      provider_result: provider_result,
      provider_request_id: "provider-request-3",
      messages_count: turn_step_messages_for(workflow_run).length,
      duration_ms: 123
    )

    assert_equal 50, result.execution_profile_fact.metadata.dig("usage_evaluation", "recommended_compaction_threshold")
    assert_equal true, result.execution_profile_fact.metadata.dig("usage_evaluation", "threshold_crossed")
  end
end
