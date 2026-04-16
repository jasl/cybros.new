require "test_helper"

class IngressAPI::Telegram::VerifyRequestTest < ActiveSupport::TestCase
  test "resolves the binding and active telegram webhook connector from the public ingress id and secret token" do
    context = telegram_verify_context

    result = IngressAPI::Telegram::VerifyRequest.call(
      public_ingress_id: context[:ingress_binding].public_ingress_id,
      secret_token: context[:plaintext_secret]
    )

    assert_equal context[:ingress_binding], result.fetch(:ingress_binding)
    assert_equal context[:channel_connector], result.fetch(:channel_connector)
  end

  test "ignores telegram poller connectors when resolving the webhook request" do
    context = telegram_verify_context
    poller_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "poller",
      label: "Primary Telegram Poller",
      lifecycle_state: "disabled",
      credential_ref_payload: {
        "bot_token" => "telegram-poller-token",
      },
      config_payload: {},
      runtime_state_payload: {}
    )

    result = IngressAPI::Telegram::VerifyRequest.call(
      public_ingress_id: context[:ingress_binding].public_ingress_id,
      secret_token: context[:plaintext_secret]
    )

    assert_equal context[:channel_connector], result.fetch(:channel_connector)
    assert_not_equal poller_connector, result.fetch(:channel_connector)
  end

  test "rejects an invalid secret token" do
    context = telegram_verify_context

    error = assert_raises(IngressAPI::Telegram::VerifyRequest::InvalidSecretToken) do
      IngressAPI::Telegram::VerifyRequest.call(
        public_ingress_id: context[:ingress_binding].public_ingress_id,
        secret_token: "wrong-secret"
      )
    end

    assert_equal "invalid telegram webhook secret token", error.message
  end

  private

  def telegram_verify_context
    context = create_workspace_context!
    plaintext_secret, secret_digest = IngressBinding.issue_ingress_secret
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      ingress_secret_digest: secret_digest,
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      }
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: "telegram_webhook",
      driver: "telegram_bot_api",
      transport_kind: "webhook",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {
        "bot_token" => "telegram-bot-token",
      },
      config_payload: {},
      runtime_state_payload: {}
    )

    context.merge(
      plaintext_secret: plaintext_secret,
      ingress_binding: ingress_binding,
      channel_connector: channel_connector
    )
  end
end
