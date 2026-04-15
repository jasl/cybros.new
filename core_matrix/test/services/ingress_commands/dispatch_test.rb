require "test_helper"

class IngressCommands::DispatchTest < ActiveSupport::TestCase
  InboundMessage = Struct.new(:public_id)

  test "stop interrupts active work without appending a new transcript turn" do
    context = dispatch_context
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

    assert_no_difference("Turn.count") do
      result = IngressCommands::Dispatch.call(command: command, context: ingress_context)

      assert result.handled?
      assert_equal "control_command", result.handled_via
      assert active_turn.reload.cancellation_requested_at.present? || active_turn.reload.canceled?
    end
  end

  test "report returns a sidecar result without mutating the main transcript" do
    context = dispatch_context
    command = IngressCommands::Parse.call(text: "/report")
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation]
    )

    assert_no_difference("Turn.count") do
      result = IngressCommands::Dispatch.call(command: command, context: ingress_context)

      assert result.handled?
      assert_equal "sidecar_query", result.handled_via
      assert_equal "report", result.command_name
      assert_predicate result.payload.dig("human_sidechat", "content"), :present?
      assert_equal "builtin", result.payload["responder_kind"]
      assert_equal result.payload.dig("machine_status", "conversation_id"), context[:conversation].public_id
    end
  end

  test "btw returns a read-only sidecar answer for the supplied question" do
    context = dispatch_context
    command = IngressCommands::Parse.call(text: "/btw what are you doing right now?")
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation]
    )

    assert_no_difference(["Turn.count", "Message.count"]) do
      result = IngressCommands::Dispatch.call(command: command, context: ingress_context)

      assert result.handled?
      assert_equal "sidecar_query", result.handled_via
      assert_equal "btw", result.command_name
      assert_equal "what are you doing right now?", result.payload["question"]
      assert_predicate result.payload.dig("human_sidechat", "content"), :present?
    end
  end

  test "regenerate stays on the transcript command path without appending a new turn" do
    context = dispatch_context
    command = IngressCommands::Parse.call(text: "/regenerate")
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation]
    )

    assert_no_difference("Turn.count") do
      result = IngressCommands::Dispatch.call(command: command, context: ingress_context)

      assert result.handled?
      assert_equal "transcript_command", result.handled_via
      assert_equal "regenerate", result.command_name
    end
  end

  private

  def dispatch_context
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
