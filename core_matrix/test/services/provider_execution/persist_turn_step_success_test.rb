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
    assert_equal "provider-request-1", result.execution_profile_fact.provider_request_id
    assert_equal "dev", result.execution_profile_fact.provider_handle
    assert_equal "mock-model", result.execution_profile_fact.model_ref
    assert_equal "chat_completions", result.execution_profile_fact.wire_api
    assert_equal 20, result.execution_profile_fact.total_tokens
    assert_equal false, result.execution_profile_fact.threshold_crossed
    assert_equal({}, result.execution_profile_fact.metadata)

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

    assert_equal 50, result.execution_profile_fact.recommended_compaction_threshold
    assert_equal true, result.execution_profile_fact.threshold_crossed
  end

  test "persists prompt cache metrics on the recorded usage event" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    provider_result = build_provider_chat_result(
      prompt_tokens_details: {
        cached_tokens: 6,
      }
    )

    result = ProviderExecution::PersistTurnStepSuccess.call(
      workflow_node: workflow_node,
      request_context: request_context,
      provider_result: provider_result,
      provider_request_id: "provider-request-cache-1",
      messages_count: turn_step_messages_for(workflow_run).length,
      duration_ms: 123
    )

    assert_equal "available", result.usage_event.prompt_cache_status
    assert_equal 6, result.usage_event.cached_input_tokens
  end

  test "dispatches final conversation output for a bound channel session after persistence succeeds" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    turn = workflow_run.turn
    turn.update!(
      origin_kind: "channel_ingress",
      origin_payload: {
        "external_message_key" => "telegram:chat:42:message:1001",
        "external_sender_id" => "telegram-user-1",
      }
    )
    ingress_binding = IngressBinding.create!(
      installation: workflow_run.installation,
      workspace_agent: workflow_run.conversation.workspace_agent,
      default_execution_runtime: workflow_run.conversation.current_execution_runtime,
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      }
    )
    channel_connector = ChannelConnector.create!(
      installation: workflow_run.installation,
      ingress_binding: ingress_binding,
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "webhook",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {
        "bot_token" => "telegram-bot-token"
      },
      config_payload: {},
      runtime_state_payload: {}
    )
    ChannelSession.create!(
      installation: workflow_run.installation,
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: workflow_run.conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "42",
      thread_key: nil,
      session_metadata: {}
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    provider_result = build_provider_chat_result
    dispatched = []
    original_dispatch = ChannelDeliveries::DispatchConversationOutput.method(:call)
    ChannelDeliveries::DispatchConversationOutput.singleton_class.send(:define_method, :call) do |**kwargs|
      dispatched << kwargs
      []
    end

    result = ProviderExecution::PersistTurnStepSuccess.call(
      workflow_node: workflow_node,
      request_context: request_context,
      provider_result: provider_result,
      provider_request_id: "provider-request-telegram-1",
      messages_count: turn_step_messages_for(workflow_run).length,
      duration_ms: 123
    )

    assert_equal 1, dispatched.length
    assert_equal workflow_run.conversation, dispatched.first.fetch(:conversation)
    assert_equal turn, dispatched.first.fetch(:turn)
    assert_equal result.output_message, dispatched.first.fetch(:message)
  ensure
    ChannelDeliveries::DispatchConversationOutput.singleton_class.send(:define_method, :call, original_dispatch)
  end
end
