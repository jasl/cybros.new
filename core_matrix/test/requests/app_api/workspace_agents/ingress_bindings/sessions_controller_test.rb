require "test_helper"

class AppApiWorkspaceAgentIngressBindingSessionsControllerTest < ActionDispatch::IntegrationTest
  test "lists sessions nested under the binding owner" do
    context = ingress_session_context
    session = create_session!(user: context[:user])
    channel_session = create_channel_session!(context, peer_id: "telegram-user-1")
    other_binding = create_ingress_binding!(context, platform: "telegram", label: "Other Telegram")
    other_connector = other_binding.channel_connectors.order(:id).last
    create_channel_session!(
      context.merge(ingress_binding: other_binding, channel_connector: other_connector),
      peer_id: "telegram-user-2"
    )

    get "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{context[:ingress_binding].public_id}/sessions",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "ingress_binding_sessions_index", response.parsed_body.fetch("method_id")
    assert_equal [channel_session.public_id], response.parsed_body.fetch("sessions").map { |item| item.fetch("channel_session_id") }
  end

  test "rebinds a session to another conversation within the binding owner scope" do
    context = ingress_session_context
    session = create_session!(user: context[:user])
    channel_session = create_channel_session!(context, peer_id: "telegram-user-1")
    other_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )

    patch "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{context[:ingress_binding].public_id}/sessions/#{channel_session.public_id}",
      params: {
        conversation_id: other_conversation.public_id
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :success
    assert_equal "ingress_binding_session_update", response.parsed_body.fetch("method_id")
    assert_equal other_conversation, channel_session.reload.conversation
  end

  test "unbinds a session nested under the binding owner" do
    context = ingress_session_context
    session = create_session!(user: context[:user])
    channel_session = create_channel_session!(context, peer_id: "telegram-user-1")

    patch "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{context[:ingress_binding].public_id}/sessions/#{channel_session.public_id}",
      params: {
        binding_state: "unbound"
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :success
    assert_equal "unbound", channel_session.reload.binding_state
  end

  test "rejects rebinding a session to a conversation owned by another workspace agent" do
    context = ingress_session_context
    session = create_session!(user: context[:user])
    channel_session = create_channel_session!(context, peer_id: "telegram-user-1")
    other_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      agent: context[:agent],
      default_execution_runtime: context[:execution_runtime]
    )
    foreign_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: other_workspace,
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )

    patch "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{context[:ingress_binding].public_id}/sessions/#{channel_session.public_id}",
      params: {
        conversation_id: foreign_conversation.public_id
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :not_found
    assert_equal channel_session.conversation_id, channel_session.reload.conversation_id
  end

  private

  def ingress_session_context
    context = create_workspace_context!
    ingress_binding = create_ingress_binding!(context, platform: "telegram")

    context.merge(
      ingress_binding: ingress_binding,
      channel_connector: ingress_binding.channel_connectors.order(:id).last
    )
  end

  def create_ingress_binding!(context, platform:, label: "#{platform.titleize} Binding")
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

    ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: platform,
      driver: platform == "telegram" ? "telegram_bot_api" : "claw_bot_sdk_weixin",
      transport_kind: platform == "telegram" ? "webhook" : "poller",
      label: label,
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )

    ingress_binding
  end

  def create_channel_session!(context, peer_id:)
    ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: create_conversation_record!(
        installation: context[:installation],
        workspace: context[:workspace],
        workspace_agent: context[:workspace_agent],
        agent: context[:agent],
        execution_runtime: context[:execution_runtime]
      ),
      platform: "telegram",
      peer_kind: "dm",
      peer_id: peer_id,
      thread_key: nil,
      session_metadata: {}
    )
  end
end
