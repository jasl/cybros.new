require "test_helper"

class Conversations::ManagedPolicyTest < ActiveSupport::TestCase
  test "projects channel-managed ownership with public ids only" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
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
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: IngressBinding::DEFAULT_MANUAL_ENTRY_POLICY
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "poller",
      label: "Telegram Poller",
      lifecycle_state: "active",
      credential_ref_payload: { "bot_token" => "123:abc" },
      config_payload: {},
      runtime_state_payload: {}
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "42",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )

    projection = Conversations::ManagedPolicy.call(conversation: conversation)

    assert_equal true, projection.fetch("managed")
    assert_equal "channel_ingress", projection.fetch("manager_kind")
    assert_equal [channel_session.public_id], projection.fetch("channel_session_ids")
    assert_equal [ingress_binding.public_id], projection.fetch("ingress_binding_ids")
    assert_equal ["telegram"], projection.fetch("platforms")
    refute_includes JSON.generate(projection), %("#{channel_session.id}")
    refute_includes JSON.generate(projection), %("#{ingress_binding.id}")
  end

  test "projects subagent-managed ownership with public ids only" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    managed_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      parent_conversation: owner_conversation,
      kind: "fork",
      entry_policy_payload: agent_internal_entry_policy_payload
    )
    subagent_connection = SubagentConnection.create!(
      installation: context[:installation],
      conversation: managed_conversation,
      owner_conversation: owner_conversation,
      user: managed_conversation.user,
      workspace: managed_conversation.workspace,
      agent: managed_conversation.agent,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0
    )

    projection = Conversations::ManagedPolicy.call(conversation: managed_conversation)

    assert_equal true, projection.fetch("managed")
    assert_equal "subagent", projection.fetch("manager_kind")
    assert_equal subagent_connection.public_id, projection.fetch("subagent_connection_id")
    assert_equal owner_conversation.public_id, projection.fetch("owner_conversation_id")
    refute_includes JSON.generate(projection), %("#{subagent_connection.id}")
    refute_includes JSON.generate(projection), %("#{owner_conversation.id}")
  end
end
