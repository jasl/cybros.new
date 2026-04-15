require "test_helper"

class IngressAPI::Preprocessors::DispatchCommandTest < ActiveSupport::TestCase
  test "handles sidecar commands before normal batching and does not mutate the main transcript" do
    context = ingress_command_context
    envelope = IngressAPI::Envelope.new(
      platform: "telegram",
      driver: "telegram_bot_api",
      ingress_binding_public_id: context[:ingress_binding].public_id,
      channel_connector_public_id: context[:channel_connector].public_id,
      external_event_key: "telegram:update:2001",
      external_message_key: "telegram:chat:1:message:2001",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      external_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      text: "/report",
      attachments: [],
      reply_to_external_message_key: nil,
      quoted_external_message_key: nil,
      quoted_text: nil,
      quoted_sender_label: nil,
      quoted_attachment_refs: [],
      occurred_at: Time.current,
      transport_metadata: {},
      raw_payload: {}
    )
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      envelope: envelope,
      pipeline_trace: []
    )

    assert_no_difference("Turn.count") do
      IngressAPI::Preprocessors::DispatchCommand.call(context: ingress_context)
    end

    assert ingress_context.result.handled?
    assert_equal "sidecar_query", ingress_context.result.handled_via
    assert_equal "report", ingress_context.result.command_name
    assert_predicate ingress_context.result.payload.dig("human_sidechat", "content"), :present?
    assert_nil ingress_context.dispatch_decision
  end

  private

  def ingress_command_context
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
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      channel_session: channel_session
    )
  end
end
