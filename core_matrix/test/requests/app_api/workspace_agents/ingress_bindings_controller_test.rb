require "test_helper"

class AppApiWorkspaceAgentIngressBindingsControllerTest < ActionDispatch::IntegrationTest
  test "creates a binding and attached connector under the workspace agent" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    runtime = create_execution_runtime!(installation: context[:installation], display_name: "Ingress Runtime")
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: runtime)

    assert_difference(["IngressBinding.count", "ChannelConnector.count"], +1) do
      post "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings",
        params: {
          platform: "telegram",
          label: "Ops Telegram",
          default_execution_runtime_id: runtime.public_id
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :created
    ingress_binding = IngressBinding.order(:id).last
    channel_connector = ingress_binding.channel_connectors.order(:id).last

    assert_equal "ingress_binding_create", response.parsed_body.fetch("method_id")
    assert_equal context[:workspace_agent].public_id, response.parsed_body.fetch("workspace_agent_id")
    assert_equal ingress_binding.public_id, response.parsed_body.dig("ingress_binding", "ingress_binding_id")
    assert_equal runtime.public_id, response.parsed_body.dig("ingress_binding", "default_execution_runtime_id")
    assert_equal ingress_binding.public_ingress_id, response.parsed_body.dig("ingress_binding", "public_ingress_id")
    assert_equal channel_connector.public_id, response.parsed_body.dig("ingress_binding", "channel_connector", "channel_connector_id")
    assert_equal "telegram", response.parsed_body.dig("ingress_binding", "channel_connector", "platform")
    assert_equal "telegram_bot_api", response.parsed_body.dig("ingress_binding", "channel_connector", "driver")
    assert_equal "webhook", response.parsed_body.dig("ingress_binding", "channel_connector", "transport_kind")
    assert_equal "active", response.parsed_body.dig("ingress_binding", "channel_connector", "lifecycle_state")
    assert_equal "telegram", response.parsed_body.dig("ingress_binding", "setup", "platform")
    assert_includes response.parsed_body.dig("ingress_binding", "setup", "webhook_path"), ingress_binding.public_ingress_id
  end

  test "disables a binding scoped through the workspace agent" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    ingress_binding = create_ingress_binding!(context, platform: "telegram")

    patch "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{ingress_binding.public_id}",
      params: {
        lifecycle_state: "disabled"
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :success
    assert_equal "ingress_binding_update", response.parsed_body.fetch("method_id")
    assert_equal "disabled", ingress_binding.reload.lifecycle_state
    assert_equal "disabled", ingress_binding.channel_connectors.order(:id).last.lifecycle_state
  end

  test "does not expose bindings outside the workspace agent owner scope" do
    context = create_workspace_context!
    owner_binding = create_ingress_binding!(context, platform: "telegram")
    foreign_user = create_user!(installation: context[:installation])
    foreign_workspace = create_workspace!(installation: context[:installation], user: foreign_user)
    foreign_agent = create_agent!(installation: context[:installation])
    create_workspace_agent!(
      installation: context[:installation],
      workspace: foreign_workspace,
      agent: foreign_agent
    )
    foreign_session = create_session!(user: foreign_user)

    post "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings",
      params: {
        platform: "telegram"
      },
      headers: app_api_headers(foreign_session.plaintext_token),
      as: :json

    assert_response :not_found

    patch "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{owner_binding.public_id}",
      params: {
        lifecycle_state: "disabled"
      },
      headers: app_api_headers(foreign_session.plaintext_token),
      as: :json

    assert_response :not_found
  end

  private

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
end
