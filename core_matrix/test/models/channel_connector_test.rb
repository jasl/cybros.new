require "test_helper"

class ChannelConnectorTest < ActiveSupport::TestCase
  test "generates a public id and resolves by public id" do
    connector = create_channel_connector!

    assert connector.public_id.present?
    assert_equal connector, ChannelConnector.find_by_public_id!(connector.public_id)
  end

  test "belongs to an ingress binding and allows only one active connector per binding" do
    context = ingress_binding_context

    ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "poller",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )

    duplicate = ChannelConnector.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "poller",
      label: "Duplicate Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )

    assert_equal :belongs_to, ChannelConnector.reflect_on_association(:ingress_binding)&.macro
    assert_not duplicate.valid?
    assert duplicate.errors[:ingress_binding_id].present? || duplicate.errors[:base].present?
  end

  test "accepts telegram webhook as a distinct connector platform" do
    connector = create_channel_connector!(
      platform: "telegram_webhook",
      transport_kind: "webhook",
      label: "Primary Telegram Webhook"
    )

    assert_equal "telegram_webhook", connector.platform
    assert_equal "webhook", connector.transport_kind
  end

  private

  def ingress_binding_context
    context = create_workspace_context!
    context.merge(
      ingress_binding: IngressBinding.create!(
        installation: context[:installation],
        workspace_agent: context[:workspace_agent],
        default_execution_runtime: context[:execution_runtime],
        routing_policy_payload: {},
        manual_entry_policy: {
          "allow_app_entry" => true,
          "allow_external_entry" => true,
        }
      )
    )
  end

  def create_channel_connector!(**attrs)
    context = ingress_binding_context

    ChannelConnector.create!({
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "poller",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {},
    }.merge(attrs))
  end
end
