require "test_helper"

class AppApiWorkspaceAgentIngressBindingPairingRequestsControllerTest < ActionDispatch::IntegrationTest
  test "lists pairing requests nested under the binding owner" do
    context = ingress_binding_context
    session = create_session!(user: context[:user])
    pairing_request = create_pairing_request!(context, platform_sender_id: "telegram-user-1")
    other_binding = create_ingress_binding!(context, platform: "telegram", label: "Other Telegram")
    create_pairing_request!(context.merge(ingress_binding: other_binding), platform_sender_id: "telegram-user-2")

    get "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{context[:ingress_binding].public_id}/pairing_requests",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "ingress_binding_pairing_requests_index", response.parsed_body.fetch("method_id")
    assert_equal [pairing_request.public_id], response.parsed_body.fetch("pairing_requests").map { |item| item.fetch("pairing_request_id") }
  end

  test "approves a pairing request nested under the binding owner" do
    context = ingress_binding_context
    session = create_session!(user: context[:user])
    pairing_request = create_pairing_request!(context, platform_sender_id: "telegram-user-1")

    patch "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{context[:ingress_binding].public_id}/pairing_requests/#{pairing_request.public_id}",
      params: {
        lifecycle_state: "approved"
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :success
    assert_equal "ingress_binding_pairing_request_update", response.parsed_body.fetch("method_id")
    assert_equal "approved", pairing_request.reload.lifecycle_state
    assert pairing_request.approved_at.present?
  end

  test "does not expose pairing requests through another binding" do
    context = ingress_binding_context
    session = create_session!(user: context[:user])
    pairing_request = create_pairing_request!(context, platform_sender_id: "telegram-user-1")
    other_binding = create_ingress_binding!(context, platform: "telegram", label: "Other Telegram")

    get "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{other_binding.public_id}/pairing_requests",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_empty response.parsed_body.fetch("pairing_requests")

    patch "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{other_binding.public_id}/pairing_requests/#{pairing_request.public_id}",
      params: {
        lifecycle_state: "approved"
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :not_found
  end

  private

  def ingress_binding_context
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

  def create_pairing_request!(context, platform_sender_id:)
    channel_connector = context[:channel_connector]
    if channel_connector.blank? || channel_connector.ingress_binding_id != context[:ingress_binding].id
      channel_connector = context[:ingress_binding].channel_connectors.order(:id).last
    end

    ChannelPairingRequest.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: channel_connector,
      platform_sender_id: platform_sender_id,
      sender_snapshot: { "label" => platform_sender_id },
      pairing_code_digest: Digest::SHA256.hexdigest(unique_test_token("pairing-code")),
      lifecycle_state: "pending",
      expires_at: 30.minutes.from_now
    )
  end
end
