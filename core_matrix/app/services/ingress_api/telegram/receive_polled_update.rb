module IngressAPI
  module Telegram
    class ReceivePolledUpdate
      PollerAdapter = Struct.new(:ingress_binding, :channel_connector, keyword_init: true) do
        include IngressAPI::TransportAdapter

        def verify_request!(raw_payload:, request_metadata:)
          {
            ingress_binding: ingress_binding,
            channel_connector: channel_connector,
          }
        end

        def normalize_envelope(raw_payload:, ingress_binding:, channel_connector:, request_metadata:)
          IngressAPI::Telegram::NormalizeUpdate.call(
            update_payload: raw_payload,
            ingress_binding: ingress_binding,
            channel_connector: channel_connector
          )
        end

        def download_attachment(client:, attachment_descriptor:, bot_token:)
          IngressAPI::Telegram::DownloadAttachment.call(
            client: client,
            attachment_descriptor: attachment_descriptor,
            bot_token: bot_token
          )
        end

        def send_delivery(channel_delivery:, client: nil)
          ChannelDeliveries::SendTelegramReply.call(
            channel_delivery: channel_delivery,
            client: client
          )
        end
      end

      def self.call(...)
        new(...).call
      end

      def initialize(channel_connector:, update:, receive_event: IngressAPI::ReceiveEvent)
        @channel_connector = channel_connector
        @update = update.deep_stringify_keys
        @receive_event = receive_event
      end

      def call
        @receive_event.call(
          adapter: PollerAdapter.new(
            ingress_binding: @channel_connector.ingress_binding,
            channel_connector: @channel_connector
          ),
          raw_payload: @update,
          request_metadata: {
            "source" => "telegram_poller",
            "ingress_binding" => @channel_connector.ingress_binding,
            "channel_connector" => @channel_connector,
            "channel_connector_id" => @channel_connector.public_id,
          }
        )
      end
    end
  end
end
