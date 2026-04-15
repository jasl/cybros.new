module ClawBotSDK
  module Weixin
    class Poller
      def self.call(...)
        new(...).call
      end

      def initialize(channel_connector:, client: nil)
        @channel_connector = channel_connector
        @client = client || ClawBotSDK::Weixin::Client.for_channel_connector(channel_connector)
      end

      def call
        runtime_state = @channel_connector.runtime_state_payload.deep_stringify_keys
        response = @client.get_updates(get_updates_buf: runtime_state["get_updates_buf"])
        @channel_connector.update!(
          runtime_state_payload: runtime_state.merge(
            "get_updates_buf" => response["get_updates_buf"],
            "last_polled_at" => Time.current.iso8601
          ).compact
        )

        Array(response["msgs"]).map(&:deep_stringify_keys)
      end
    end
  end
end
