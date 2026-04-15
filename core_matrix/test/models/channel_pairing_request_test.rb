require "test_helper"

class ChannelPairingRequestTest < ActiveSupport::TestCase
  test "generates a public id and resolves by public id" do
    pairing_request = create_channel_pairing_request!

    assert pairing_request.public_id.present?
    assert_equal pairing_request, ChannelPairingRequest.find_by_public_id!(pairing_request.public_id)
  end

  test "allows only one active pending pairing request per sender and connector" do
    context = channel_pairing_request_context

    ChannelPairingRequest.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      platform_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      pairing_code_digest: Digest::SHA256.hexdigest(unique_test_token("pairing-code")),
      lifecycle_state: "pending",
      expires_at: 30.minutes.from_now
    )

    duplicate = ChannelPairingRequest.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      platform_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      pairing_code_digest: Digest::SHA256.hexdigest(unique_test_token("pairing-code")),
      lifecycle_state: "pending",
      expires_at: 30.minutes.from_now
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:platform_sender_id].present? || duplicate.errors[:channel_connector_id].present? || duplicate.errors[:base].present?
  end

  test "allows a new pending request after the prior request is resolved" do
    context = channel_pairing_request_context
    resolved = ChannelPairingRequest.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      platform_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      pairing_code_digest: Digest::SHA256.hexdigest(unique_test_token("pairing-code")),
      lifecycle_state: "approved",
      expires_at: 30.minutes.from_now
    )

    replacement = ChannelPairingRequest.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      platform_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      pairing_code_digest: Digest::SHA256.hexdigest(unique_test_token("pairing-code")),
      lifecycle_state: "pending",
      expires_at: 30.minutes.from_now
    )

    assert_predicate resolved, :approved?
    assert_predicate replacement, :valid?
  end

  private

  def channel_pairing_request_context
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

    context.merge(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector
    )
  end

  def create_channel_pairing_request!(**attrs)
    context = channel_pairing_request_context

    ChannelPairingRequest.create!({
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      platform_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      pairing_code_digest: Digest::SHA256.hexdigest(unique_test_token("pairing-code")),
      lifecycle_state: "pending",
      expires_at: 30.minutes.from_now,
    }.merge(attrs))
  end
end
