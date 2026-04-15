module ChannelDeliveries
  class SendWeixinReply
    include Rails.application.routes.url_helpers

    def self.call(...)
      new(...).call
    end

    def initialize(channel_delivery:, client: nil, media_client: nil)
      @channel_delivery = channel_delivery
      @client = client
      @media_client = media_client
    end

    def call
      response =
        if typing_delivery?
          ensure_typing_ticket!
          client.send_typing(
            ilink_user_id: @channel_delivery.channel_session.peer_id,
            typing_ticket: typing_ticket
          )
        elsif attachments.present?
          attachments.each_with_index.map do |attachment, index|
            if native_delivery_attachment?(attachment)
              attachment_record = attachment_record(attachment)
              media_client.send_attachment(
                attachment_record: attachment_record,
                descriptor: attachment,
                to_user_id: @channel_delivery.channel_session.peer_id,
                context_token: context_token,
                text: attachment_caption(index)
              )
            else
              client.send_text(
                to_user_id: @channel_delivery.channel_session.peer_id,
                text: signed_link_text(attachment, index),
                context_token: context_token
              )
            end
          end
        else
          client.send_text(
            to_user_id: @channel_delivery.channel_session.peer_id,
            text: payload.fetch("text"),
            context_token: context_token
          )
        end

      mark_delivered!(response)
      response
    rescue StandardError => error
      @channel_delivery.update!(
        delivery_state: "failed",
        failure_payload: @channel_delivery.failure_payload.merge(
          "error_class" => error.class.name,
          "error_message" => error.message
        )
      )
      raise
    end

    private

    def payload
      @payload ||= @channel_delivery.payload.deep_stringify_keys
    end

    def attachments
      Array(payload["attachments"]).map(&:deep_stringify_keys)
    end

    def typing_delivery?
      payload["chat_action"] == "typing"
    end

    def client
      @client ||= ClawBotSDK::Weixin::Client.for_channel_connector(@channel_delivery.channel_connector)
    end

    def media_client
      @media_client ||= ClawBotSDK::Weixin::MediaClient.new(client:)
    end

    def context_token
      ClawBotSDK::Weixin::ContextTokenStore.fetch(channel_session: @channel_delivery.channel_session)
    end

    def native_delivery_attachment?(attachment)
      return true unless attachment["attachment_id"].present?

      Attachments::CreateForMessage.native_delivery?(
        attachment: attachment_record(attachment),
        descriptor: attachment
      )
    end

    def attachment_caption(index)
      return nil unless index.zero?

      payload["text"]
    end

    def signed_link_text(attachment, index)
      lines = []
      lines << payload["text"] if index.zero? && payload["text"].present?
      lines << attachment.fetch("filename", "attachment")
      lines << Attachments::CreateForMessage.signed_download_url(
        attachment: attachment_record(attachment),
        host: public_url_options
      )
      lines.join("\n")
    end

    def attachment_record(attachment)
      @attachment_records ||= {}
      @attachment_records[attachment.fetch("attachment_id")] ||= MessageAttachment.find_by_public_id!(attachment.fetch("attachment_id"))
    end

    def typing_ticket
      @channel_delivery.channel_connector.runtime_state_payload.deep_stringify_keys["typing_ticket"]
    end

    def ensure_typing_ticket!
      return if typing_ticket.present?

      config = client.get_config(
        ilink_user_id: @channel_delivery.channel_session.peer_id,
        context_token: context_token
      )
      runtime_state = @channel_delivery.channel_connector.runtime_state_payload.deep_stringify_keys
      @channel_delivery.channel_connector.update!(
        runtime_state_payload: runtime_state.merge(
          "typing_ticket" => config["typing_ticket"]
        )
      )
    end

    def mark_delivered!(response)
      attributes = { delivery_state: "delivered" }
      responses = response.is_a?(Array) ? response : [response]
      response_payload = responses.find { |item| item.is_a?(Hash) && item["message_id"].present? }
      if response_payload.present?
        attributes[:external_message_key] = "weixin:peer:#{@channel_delivery.channel_session.peer_id}:message:#{response_payload.fetch("message_id")}"
      end

      @channel_delivery.update!(attributes)
    end

    def public_url_options
      Rails.application.routes.default_url_options.presence ||
        ActionMailer::Base.default_url_options
    end
  end
end
