require "test_helper"

class IngressAPI::Preprocessors::CreateOrBindConversationTest < ActiveSupport::TestCase
  test "creates a root conversation from the binding workspace agent and binding default runtime when the session is unbound" do
    context = create_workspace_context!
    binding_runtime = create_execution_runtime!(installation: context[:installation], display_name: "Binding Runtime")
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: binding_runtime)
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: binding_runtime,
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
      transport_kind: "poller",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )
    previous_conversation = create_conversation_record!(
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
      conversation: previous_conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      binding_state: "unbound",
      session_metadata: {}
    )
    ingress_context = IngressAPI::Context.new(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session,
      pipeline_trace: []
    )

    IngressAPI::Preprocessors::CreateOrBindConversation.call(context: ingress_context)

    assert ingress_context.conversation.present?
    assert_not_equal previous_conversation, ingress_context.conversation
    assert_equal context[:workspace_agent], ingress_context.conversation.workspace_agent
    assert_equal binding_runtime, ingress_context.conversation.current_execution_runtime
    assert_equal Conversation.channel_managed_entry_policy_payload(
      base_policy_payload: context[:workspace_agent].entry_policy_payload,
      purpose: "interactive"
    ), ingress_context.conversation.entry_policy_payload
    assert_equal ingress_context.conversation, channel_session.reload.conversation
    assert_equal "active", channel_session.binding_state
  end

  test "reuses the bound conversation when the session is already active" do
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
      transport_kind: "poller",
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
      binding_state: "active",
      session_metadata: {}
    )
    ingress_context = IngressAPI::Context.new(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session,
      pipeline_trace: []
    )

    IngressAPI::Preprocessors::CreateOrBindConversation.call(context: ingress_context)

    assert_equal conversation, ingress_context.conversation
    assert_equal conversation, channel_session.reload.conversation
  end

  test "rebinds archived conversations to a fresh managed root" do
    context = create_workspace_context!
    ingress_binding, channel_connector = create_binding_context(context)
    archived_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      entry_policy_payload: Conversation.channel_managed_entry_policy_payload(
        base_policy_payload: context[:workspace_agent].entry_policy_payload,
        purpose: "interactive"
      )
    )
    archived_conversation.update!(lifecycle_state: "archived")
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: archived_conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )
    ingress_context = IngressAPI::Context.new(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session,
      pipeline_trace: []
    )

    assert_difference("Conversation.count", 1) do
      IngressAPI::Preprocessors::CreateOrBindConversation.call(context: ingress_context)
    end

    assert_not_equal archived_conversation, ingress_context.conversation
    assert_equal ingress_context.conversation, channel_session.reload.conversation
    assert_equal Conversation.channel_managed_entry_policy_payload(
      base_policy_payload: context[:workspace_agent].entry_policy_payload,
      purpose: "interactive"
    ), ingress_context.conversation.entry_policy_payload
  end

  test "rebinds deleted conversations to a fresh managed root" do
    context = create_workspace_context!
    ingress_binding, channel_connector = create_binding_context(context)
    deleted_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      entry_policy_payload: Conversation.channel_managed_entry_policy_payload(
        base_policy_payload: context[:workspace_agent].entry_policy_payload,
        purpose: "interactive"
      ),
      deletion_state: "pending_delete",
      deleted_at: Time.current
    )
    deleted_conversation.update!(deletion_state: "deleted")
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: deleted_conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )
    ingress_context = IngressAPI::Context.new(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session,
      pipeline_trace: []
    )

    assert_difference("Conversation.count", 1) do
      IngressAPI::Preprocessors::CreateOrBindConversation.call(context: ingress_context)
    end

    assert_not_equal deleted_conversation, ingress_context.conversation
    assert_equal ingress_context.conversation, channel_session.reload.conversation
  end

  private

  def create_binding_context(context)
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
      transport_kind: "poller",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )

    [ingress_binding, channel_connector]
  end
end
