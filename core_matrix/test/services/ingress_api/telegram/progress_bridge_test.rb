require "test_helper"

class IngressAPI::Telegram::ProgressBridgeTest < ActiveSupport::TestCase
  test "projects assistant output streaming to typing and editable preview delivery" do
    context = progress_context
    original_sender = ChannelDeliveries::SendTelegramReply.method(:call)
    ChannelDeliveries::SendTelegramReply.singleton_class.send(:define_method, :call) do |channel_delivery:, **|
      next_message_id = channel_delivery.payload["preview_message_id"].presence || 501
      channel_delivery.update!(
        delivery_state: "delivered",
        external_message_key: "telegram:chat:telegram-user-1:message:#{next_message_id}"
      )
      channel_delivery
    end

    ConversationRuntime::PublishEvent.call(
      conversation: context[:conversation],
      turn: context[:turn],
      event_kind: "runtime.assistant_output.started",
      payload: {
        "stream_id" => "turn-output:#{context[:turn].public_id}",
        "workflow_run_id" => context[:workflow_run].public_id,
        "workflow_node_id" => context[:workflow_node].public_id,
      },
      progress_dispatcher: ChannelDeliveries::DispatchRuntimeProgress
    )
    ConversationRuntime::PublishEvent.call(
      conversation: context[:conversation],
      turn: context[:turn],
      event_kind: "runtime.assistant_output.delta",
      payload: {
        "stream_id" => "turn-output:#{context[:turn].public_id}",
        "workflow_run_id" => context[:workflow_run].public_id,
        "workflow_node_id" => context[:workflow_node].public_id,
        "sequence" => 1,
        "delta" => "Hel",
      },
      progress_dispatcher: ChannelDeliveries::DispatchRuntimeProgress
    )
    ConversationRuntime::PublishEvent.call(
      conversation: context[:conversation],
      turn: context[:turn],
      event_kind: "runtime.assistant_output.delta",
      payload: {
        "stream_id" => "turn-output:#{context[:turn].public_id}",
        "workflow_run_id" => context[:workflow_run].public_id,
        "workflow_node_id" => context[:workflow_node].public_id,
        "sequence" => 2,
        "delta" => "lo",
      },
      progress_dispatcher: ChannelDeliveries::DispatchRuntimeProgress
    )

    deliveries = ChannelDelivery.order(:id).to_a

    assert_equal 3, deliveries.length
    assert_equal "typing", deliveries.first.payload["chat_action"]
    assert_equal "preview_stream", deliveries.second.payload["delivery_mode"]
    assert_nil deliveries.second.payload["preview_message_id"]
    assert_equal "preview_stream", deliveries.third.payload["delivery_mode"]
    assert_predicate deliveries.third.payload["preview_message_id"], :present?
  ensure
    ChannelDeliveries::SendTelegramReply.singleton_class.send(:define_method, :call, original_sender)
  end

  test "projects assistant output streaming for telegram webhook sessions too" do
    context = progress_context(platform: "telegram_webhook")
    original_sender = ChannelDeliveries::SendTelegramReply.method(:call)
    ChannelDeliveries::SendTelegramReply.singleton_class.send(:define_method, :call) do |channel_delivery:, **|
      channel_delivery.update!(
        delivery_state: "delivered",
        external_message_key: "telegram:chat:telegram-user-1:message:700"
      )
      channel_delivery
    end

    ConversationRuntime::PublishEvent.call(
      conversation: context[:conversation],
      turn: context[:turn],
      event_kind: "runtime.assistant_output.started",
      payload: {
        "stream_id" => "turn-output:#{context[:turn].public_id}",
        "workflow_run_id" => context[:workflow_run].public_id,
        "workflow_node_id" => context[:workflow_node].public_id,
      },
      progress_dispatcher: ChannelDeliveries::DispatchRuntimeProgress
    )

    delivery = ChannelDelivery.order(:id).last
    assert_predicate delivery, :present?
    assert_equal "telegram_webhook", delivery.channel_connector.platform
    assert_equal "typing", delivery.payload["chat_action"]
  ensure
    ChannelDeliveries::SendTelegramReply.singleton_class.send(:define_method, :call, original_sender)
  end

  private

  def progress_context(platform: "telegram")
    context = create_workspace_context!
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      }
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: platform,
      driver: "telegram_bot_api",
      transport_kind: platform == "telegram_webhook" ? "webhook" : "poller",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {
        "bot_token" => "telegram-bot-token",
      },
      config_payload: {},
      runtime_state_payload: {}
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: platform,
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      session_metadata: {}
    )
    turn = Turns::StartChannelIngressTurn.call(
      conversation: conversation,
      channel_inbound_message: Struct.new(:public_id).new("channel-inbound-1"),
      content: "Original inbound input",
      origin_payload: {
        "ingress_binding_id" => ingress_binding.public_id,
        "channel_connector_id" => channel_connector.public_id,
        "channel_session_id" => channel_session.public_id,
        "external_message_key" => "telegram:chat:telegram-user-1:message:1000",
        "external_sender_id" => "telegram-user-1",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run, node_key: "turn_step", node_type: "turn_step")

    context.merge(
      conversation: conversation,
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session,
      turn: turn,
      workflow_run: workflow_run,
      workflow_node: workflow_node
    )
  end
end
