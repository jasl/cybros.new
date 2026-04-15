require "test_helper"

class IngressCommands::AuthorizeTest < ActiveSupport::TestCase
  InboundMessage = Struct.new(:public_id)

  test "allows stop only for the sender who owns the active work in a shared conversation" do
    context = ingress_authorization_context
    active_turn = Turns::StartChannelIngressTurn.call(
      conversation: context[:conversation],
      channel_inbound_message: InboundMessage.new("channel-inbound-1"),
      content: "active work",
      origin_payload: {
        "ingress_binding_id" => context[:ingress_binding].public_id,
        "channel_connector_id" => context[:channel_connector].public_id,
        "channel_session_id" => context[:channel_session].public_id,
        "external_sender_id" => "telegram-user-1",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )
    command = IngressCommands::Parse.call(text: "/stop")
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      active_turn: active_turn
    )

    allowed = IngressCommands::Authorize.call(
      command: command,
      context: ingress_context,
      sender_external_id: "telegram-user-1"
    )
    denied = IngressCommands::Authorize.call(
      command: command,
      context: ingress_context,
      sender_external_id: "telegram-user-2"
    )

    assert allowed.allowed?
    assert_not denied.allowed?
    assert_equal "sender_mismatch", denied.rejection_reason
  end

  test "rejects stop when the active work is missing sender provenance" do
    context = ingress_authorization_context
    active_turn = Turns::StartChannelIngressTurn.call(
      conversation: context[:conversation],
      channel_inbound_message: InboundMessage.new("channel-inbound-2"),
      content: "active work",
      origin_payload: {
        "ingress_binding_id" => context[:ingress_binding].public_id,
        "channel_connector_id" => context[:channel_connector].public_id,
        "channel_session_id" => context[:channel_session].public_id,
        "external_sender_id" => "telegram-user-1",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )
    active_turn.update_column(:origin_payload, {})
    command = IngressCommands::Parse.call(text: "/stop")
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      active_turn: active_turn.reload
    )

    authorization = IngressCommands::Authorize.call(
      command: command,
      context: ingress_context,
      sender_external_id: "telegram-user-1"
    )

    assert_not authorization.allowed?
    assert_equal "missing_sender_provenance", authorization.rejection_reason
  end

  test "rejects btw when the question is blank" do
    context = ingress_authorization_context
    command = IngressCommands::Parse.call(text: "/btw")
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation]
    )

    authorization = IngressCommands::Authorize.call(
      command: command,
      context: ingress_context,
      sender_external_id: "telegram-user-1"
    )

    assert_not authorization.allowed?
    assert_equal "missing_question", authorization.rejection_reason
  end

  test "gates regenerate through workspace agent capabilities" do
    context = create_workspace_context!
    context[:workspace_agent].update!(capability_policy_payload: { "disabled_capabilities" => ["regenerate"] })
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    command = IngressCommands::Parse.call(text: "/regenerate")
    ingress_context = IngressAPI::Context.new(
      ingress_binding: IngressBinding.create!(
        installation: context[:installation],
        workspace_agent: context[:workspace_agent],
        default_execution_runtime: context[:execution_runtime],
        routing_policy_payload: {},
        manual_entry_policy: {
          "allow_app_entry" => true,
          "allow_external_entry" => true,
        }
      ),
      conversation: conversation
    )

    authorization = IngressCommands::Authorize.call(
      command: command,
      context: ingress_context,
      sender_external_id: "telegram-user-1"
    )

    assert_not authorization.allowed?
    assert_equal "capability_disabled", authorization.rejection_reason
  end

  private

  def ingress_authorization_context
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
      peer_kind: "group",
      peer_id: "telegram-group-1",
      thread_key: "topic-1",
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
