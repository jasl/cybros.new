module ClawBotSDK
  module Weixin
    class QrLogin
      def self.start(channel_connector:)
        runtime_state = channel_connector.runtime_state_payload.deep_stringify_keys
        updated_runtime_state = runtime_state.merge(
            "login_state" => "pending",
            "login_started_at" => Time.current.iso8601
          )
        channel_connector.update!(
          runtime_state_payload: updated_runtime_state
        )

        updated_runtime_state.slice(
          "login_state",
          "login_started_at",
          "account_id",
          "base_url",
          "qr_text",
          "qr_code_url"
        )
      end

      def self.status(channel_connector:)
        channel_connector.runtime_state_payload.deep_stringify_keys.slice(
          "login_state",
          "login_started_at",
          "account_id",
          "base_url",
          "qr_text",
          "qr_code_url"
        )
      end

      def self.disconnect!(channel_connector:)
        runtime_state = channel_connector.runtime_state_payload.deep_stringify_keys
        channel_connector.update!(
          lifecycle_state: "disconnected",
          runtime_state_payload: runtime_state.except(
            "bot_token",
            "account_id",
            "typing_ticket",
            "get_updates_buf",
            "qr_text",
            "qr_code_url",
            "login_started_at",
            "login_state"
          )
        )
      end
    end
  end
end
