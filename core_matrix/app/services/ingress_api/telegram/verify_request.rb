module IngressAPI
  module Telegram
    class VerifyRequest
      class InvalidSecretToken < StandardError; end

      def self.call(...)
        new(...).call
      end

      def initialize(public_ingress_id:, secret_token:)
        @public_ingress_id = public_ingress_id
        @secret_token = secret_token.to_s
      end

      def call
        ingress_binding = IngressBinding.find_by!(
          public_ingress_id: @public_ingress_id,
          lifecycle_state: "active"
        )
        raise InvalidSecretToken, "invalid telegram webhook secret token" unless ingress_binding.matches_ingress_secret?(@secret_token)

        channel_connector = ingress_binding.channel_connectors.find_by!(
          platform: "telegram",
          driver: "telegram_bot_api",
          transport_kind: "webhook",
          lifecycle_state: "active"
        )

        {
          ingress_binding: ingress_binding,
          channel_connector: channel_connector,
        }
      end
    end
  end
end
