module IngressAPI
  module Weixin
    class ReceivePolledMessage
      WeixinAdapter = Struct.new(:message, keyword_init: true) do
        include IngressAPI::TransportAdapter

        def verify_request!(raw_payload:, request_metadata:)
          request_metadata.slice("ingress_binding", "channel_connector")
        end

        def normalize_envelope(raw_payload:, ingress_binding:, channel_connector:, request_metadata:)
          ClawBotSDK::Weixin::NormalizeMessage.call(
            message: message,
            ingress_binding: ingress_binding,
            channel_connector: channel_connector
          )
        end

        def download_attachment(...)
          raise NotImplementedError
        end

        def send_delivery(channel_delivery:, client: nil)
          ChannelDeliveries::SendWeixinReply.call(
            channel_delivery: channel_delivery,
            client: client
          )
        end
      end

      def self.call(...)
        new(...).call
      end

      def initialize(channel_connector:, message:, receive_event: IngressAPI::ReceiveEvent)
        @channel_connector = channel_connector
        @message = message.deep_stringify_keys
        @receive_event = receive_event
      end

      def call
        persist_context_token! if existing_session.present? && @message["context_token"].present?

        @receive_event.call(
          adapter: WeixinAdapter.new(message: @message),
          raw_payload: @message,
          request_metadata: {
            "source" => "weixin_poller",
            "ingress_binding" => @channel_connector.ingress_binding,
            "channel_connector" => @channel_connector,
            "channel_connector_id" => @channel_connector.public_id
          }
        )
      end

      private

      def existing_session
        @existing_session ||= ChannelSession.find_by(
          installation_id: @channel_connector.installation_id,
          channel_connector_id: @channel_connector.id,
          peer_kind: "dm",
          peer_id: @message["from_user_id"].to_s,
          normalized_thread_key: ""
        )
      end

      def persist_context_token!
        ClawBotSDK::Weixin::ContextTokenStore.store!(
          channel_session: existing_session,
          context_token: @message.fetch("context_token")
        )
      end
    end
  end
end
