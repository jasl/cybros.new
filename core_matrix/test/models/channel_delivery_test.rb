require "test_helper"

class ChannelDeliveryTest < ActiveSupport::TestCase
  test "generates a public id and resolves by public id" do
    delivery = create_channel_delivery!

    assert delivery.public_id.present?
    assert_equal delivery, ChannelDelivery.find_by_public_id!(delivery.public_id)
  end

  test "rejects payload references that expose internal bigint ids" do
    context = channel_delivery_context

    delivery = ChannelDelivery.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_message_key: "telegram:chat:1:message:301",
      reply_to_external_message_key: "telegram:chat:1:message:201",
      payload: {
        "channel_session_id" => context[:channel_session].public_id,
        "conversation_id" => context[:conversation].id,
      },
      failure_payload: {}
    )

    assert_not delivery.valid?
    assert_includes delivery.errors[:payload], "must use public ids for external resource references"
  end

  test "rejects failure payload references that expose internal bigint ids" do
    context = channel_delivery_context

    delivery = ChannelDelivery.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_message_key: "telegram:chat:1:message:302",
      payload: {
        "channel_session_id" => context[:channel_session].public_id,
        "conversation_id" => context[:conversation].public_id,
      },
      failure_payload: {
        "conversation_id" => context[:conversation].id,
      }
    )

    assert_not delivery.valid?
    assert_includes delivery.errors[:failure_payload], "must use public ids for external resource references"
  end

  test "rejects optional payload references when the referenced turn is not attached" do
    context = channel_delivery_context

    delivery = ChannelDelivery.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_message_key: "telegram:chat:1:message:303",
      reply_to_external_message_key: "telegram:chat:1:message:201",
      payload: {
        "channel_session_id" => context[:channel_session].public_id,
        "conversation_id" => context[:conversation].public_id,
        "turn_id" => "turn-public-id",
      },
      failure_payload: {}
    )

    assert_not delivery.valid?
    assert_includes delivery.errors[:payload], "must use public ids for external resource references"
  end

  test "rejects deliveries whose conversation does not match the bound channel session" do
    context = channel_delivery_context
    other_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )

    delivery = ChannelDelivery.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: other_conversation,
      external_message_key: "telegram:chat:1:message:304",
      payload: {
        "channel_session_id" => context[:channel_session].public_id,
        "conversation_id" => other_conversation.public_id,
      },
      failure_payload: {}
    )

    assert_not delivery.valid?
    assert_includes delivery.errors[:conversation], "must match the bound channel session conversation"
  end

  private

  def channel_delivery_context
    context = create_workspace_context!
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
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "webhook",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      session_metadata: {}
    )

    context.merge(
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      channel_session: channel_session
    )
  end

  def create_channel_delivery!(**attrs)
    context = channel_delivery_context

    ChannelDelivery.create!({
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_message_key: "telegram:chat:1:message:301",
      reply_to_external_message_key: "telegram:chat:1:message:201",
      payload: {
        "channel_session_id" => context[:channel_session].public_id,
        "conversation_id" => context[:conversation].public_id,
      },
      failure_payload: {},
    }.merge(attrs))
  end
end
