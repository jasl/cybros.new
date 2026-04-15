module IngressAPI
  module Telegram
    class UpdatesController < IngressAPI::BaseController
      rescue_from IngressAPI::Telegram::VerifyRequest::InvalidSecretToken, with: :render_unauthorized

      TelegramAdapter = Struct.new(:public_ingress_id, :secret_token, keyword_init: true) do
        include IngressAPI::TransportAdapter

        def verify_request!(raw_payload:, request_metadata:)
          IngressAPI::Telegram::VerifyRequest.call(
            public_ingress_id: public_ingress_id,
            secret_token: secret_token
          )
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

      def create
        result = IngressAPI::ReceiveEvent.call(
          adapter: adapter,
          raw_payload: raw_payload,
          request_metadata: request_metadata
        )

        render json: {
          status: result.status,
          handled_via: result.handled_via,
          rejection_reason: result.rejection_reason
        }.compact
      end

      private

      def adapter
        @adapter ||= TelegramAdapter.new(
          public_ingress_id: params.fetch(:public_ingress_id),
          secret_token: request.headers["X-Telegram-Bot-Api-Secret-Token"].to_s
        )
      end

      def raw_payload
        request.request_parameters.deep_stringify_keys
      end

      def request_metadata
        {
          "source" => "telegram_webhook",
          "public_ingress_id" => params.fetch(:public_ingress_id),
          "remote_ip" => request.remote_ip
        }
      end

      def render_unauthorized(error)
        render json: { error: error.message }, status: :unauthorized
      end
    end
  end
end
