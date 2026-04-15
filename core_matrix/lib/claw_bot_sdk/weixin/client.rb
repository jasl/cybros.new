require "json"
require "uri"

module ClawBotSDK
  module Weixin
    class Client
      DEFAULT_TIMEOUT_MS = 15_000
      DEFAULT_LONG_POLL_TIMEOUT_MS = 35_000

      def self.for_channel_connector(channel_connector, http_client: nil)
        runtime_state = channel_connector.runtime_state_payload.deep_stringify_keys

        new(
          base_url: runtime_state.fetch("base_url"),
          bot_token: runtime_state["bot_token"],
          timeout_ms: runtime_state["timeout_ms"],
          long_poll_timeout_ms: runtime_state["long_poll_timeout_ms"],
          http_client: http_client
        )
      end

      def initialize(base_url:, bot_token:, timeout_ms: nil, long_poll_timeout_ms: nil, http_client: nil)
        @base_url = base_url
        @bot_token = bot_token
        @timeout_ms = timeout_ms.to_i.positive? ? timeout_ms.to_i : DEFAULT_TIMEOUT_MS
        @long_poll_timeout_ms = long_poll_timeout_ms.to_i.positive? ? long_poll_timeout_ms.to_i : DEFAULT_LONG_POLL_TIMEOUT_MS
        @http_client = http_client || method(:default_http_client)
      end

      def get_updates(get_updates_buf:)
        post(
          endpoint: "ilink/bot/getupdates",
          body: {
            "get_updates_buf" => get_updates_buf.to_s,
            "base_info" => base_info
          },
          timeout_ms: @long_poll_timeout_ms
        )
      end

      def send_text(to_user_id:, text:, context_token:)
        post(
          endpoint: "ilink/bot/sendmessage",
          body: {
            "msg" => {
              "to_user_id" => to_user_id,
              "message_type" => 2,
              "message_state" => 2,
              "context_token" => context_token,
              "item_list" => [
                {
                  "type" => 1,
                  "text_item" => { "text" => text }
                }
              ]
            }
          }
        )
      end

      def get_config(ilink_user_id:, context_token: nil)
        post(
          endpoint: "ilink/bot/getconfig",
          body: {
            "ilink_user_id" => ilink_user_id,
            "context_token" => context_token,
            "base_info" => base_info
          }
        )
      end

      def send_typing(ilink_user_id:, typing_ticket:)
        post(
          endpoint: "ilink/bot/sendtyping",
          body: {
            "ilink_user_id" => ilink_user_id,
            "typing_ticket" => typing_ticket,
            "status" => 1,
            "base_info" => base_info
          }
        )
      end

      def get_upload_url(payload)
        post(
          endpoint: "ilink/bot/getuploadurl",
          body: payload.deep_stringify_keys.merge("base_info" => base_info)
        )
      end

      private

      def base_info
        { "channel_version" => "core_matrix" }
      end

      def post(endpoint:, body:, timeout_ms: @timeout_ms)
        @http_client.call(
          method: "POST",
          endpoint: endpoint,
          base_url: @base_url,
          token: @bot_token,
          body: body.deep_stringify_keys,
          timeout_ms: timeout_ms
        ).deep_stringify_keys
      end

      def default_http_client(method:, endpoint:, base_url:, token:, body:, timeout_ms:)
        url = URI.join(base_url.end_with?("/") ? base_url : "#{base_url}/", endpoint).to_s
        headers = { "Content-Type" => "application/json" }
        headers["Authorization"] = "Bearer #{token}" if token.present?
        response = HTTPX.with(timeout: { operation_timeout: timeout_ms / 1000.0 })
          .request(method, url, headers:, json: body)
        raise "weixin request failed: #{response.status}" unless response.status == 200

        JSON.parse(response.to_s)
      end
    end
  end
end
