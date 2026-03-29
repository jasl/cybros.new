require "test_helper"

class Turns::StaleWorkSafetyTest < ActiveSupport::TestCase
  test "rejects provider completion when the selected input drifted after the execution snapshot froze" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    provider_result = build_provider_chat_result
    turn = workflow_run.turn

    replacement_input = UserMessage.create!(
      installation: turn.installation,
      conversation: turn.conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: turn.messages.where(slot: "input").maximum(:variant_index).to_i + 1,
      content: "Replacement input"
    )
    turn.update!(selected_input_message: replacement_input)

    assert_raises(ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError) do
      ProviderExecution::PersistTurnStepSuccess.call(
        workflow_node: workflow_node,
        request_context: request_context,
        provider_result: provider_result,
        provider_request_id: "provider-request-stale-input",
        messages_count: turn_step_messages_for(workflow_run).length,
        duration_ms: 123
      )
    end

    assert_nil turn.reload.selected_output_message
    assert_equal "active", workflow_run.reload.lifecycle_state
    assert_equal 0, UsageEvent.count
  end

  test "rejects provider completion when selector drift changed the frozen model choice" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    provider_result = build_provider_chat_result
    turn = workflow_run.turn

    turn.update!(
      resolved_model_selection_snapshot: turn.resolved_model_selection_snapshot.merge(
        "normalized_selector" => "role:other",
        "resolved_model_ref" => "other-model"
      )
    )

    assert_raises(ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError) do
      ProviderExecution::PersistTurnStepSuccess.call(
        workflow_node: workflow_node,
        request_context: request_context,
        provider_result: provider_result,
        provider_request_id: "provider-request-selector-drift",
        messages_count: turn_step_messages_for(workflow_run).length,
        duration_ms: 123
      )
    end

    assert_nil turn.reload.selected_output_message
    assert_equal "active", workflow_run.reload.lifecycle_state
    assert_equal 0, UsageEvent.count
  end
end
