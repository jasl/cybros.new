module ClawBotSDK
  module Weixin
    class QrLogin
      def self.start(channel_connector:)
        runtime_state = channel_connector.runtime_state_payload.deep_stringify_keys
        channel_connector.update!(
          runtime_state_payload: runtime_state.merge(
            "login_state" => "pending",
            "login_started_at" => Time.current.iso8601
          )
        )

        {
          "login_state" => "pending",
        }
      end

      def self.status(channel_connector:)
        channel_connector.runtime_state_payload.deep_stringify_keys.slice(
          "login_state",
          "login_started_at",
          "account_id",
          "base_url"
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
            "get_updates_buf"
          )
        )
      end
    end
  end
end
