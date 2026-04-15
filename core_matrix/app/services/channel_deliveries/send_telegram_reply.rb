module ChannelDeliveries
  class SendTelegramReply
    include Rails.application.routes.url_helpers

    def self.call(...)
      new(...).call
    end

    def initialize(channel_delivery:, client: nil)
      @channel_delivery = channel_delivery
      @client = client
    end

    def call
      response = if preview_update?
        preview_response = client.edit_message_text(
          chat_id: chat_id,
          message_id: payload.fetch("preview_message_id"),
          text: payload.fetch("text")
        )
        track_response!(preview_response)
        attachment_responses = attachments.present? ? send_attachments! : []
        [preview_response, *attachment_responses].compact
      elsif attachments.present?
        send_attachments!
      elsif payload["chat_action"].present?
        client.send_chat_action(chat_id: chat_id, action: payload.fetch("chat_action"))
      else
        message_response = client.send_message(**{
          chat_id: chat_id,
          text: payload.fetch("text"),
          reply_to_message_id: reply_to_message_id
        }.compact)
        track_response!(message_response)
        message_response
      end

      mark_delivered!(response)
      response
    rescue StandardError => error
      @channel_delivery.update!(
        delivery_state: "failed",
        failure_payload: @channel_delivery.failure_payload.merge(
          "delivered_external_message_keys" => @delivered_external_message_keys,
          "error_class" => error.class.name,
          "error_message" => error.message
        )
      )
      raise
    end

    private

    def client
      @client ||= IngressAPI::Telegram::Client.for_channel_connector(@channel_delivery.channel_connector)
    end

    def payload
      @payload ||= @channel_delivery.payload.deep_stringify_keys
    end

    def attachments
      Array(payload["attachments"]).map(&:deep_stringify_keys)
    end

    def delivered_external_message_keys
      @delivered_external_message_keys ||= []
    end

    def preview_update?
      payload["delivery_mode"] == "preview_stream" && payload["preview_message_id"].present?
    end

    def send_attachments!
      attachments.each_with_index.map do |attachment, index|
        response = if native_delivery_attachment?(attachment)
          file = attachment_io(attachment)
          caption = attachment_caption(index)

          if attachment.fetch("modality") == "image"
            client.send_photo(chat_id: chat_id, photo: file, caption: caption)
          else
            client.send_document(chat_id: chat_id, document: file, caption: caption)
          end
        else
          client.send_message(**{
            chat_id: chat_id,
            text: signed_link_text(attachment, index),
            reply_to_message_id: reply_to_message_id
          }.compact)
        end
        track_response!(response)
        response
      ensure
        file&.close if file.respond_to?(:close)
      end
    end

    def attachment_io(attachment)
      if attachment["path"].present?
        File.open(attachment.fetch("path"), "rb")
      elsif attachment["attachment_id"].present?
        message_attachment = MessageAttachment.find_by_public_id!(attachment.fetch("attachment_id"))
        message_attachment.file.blob.open
      else
        raise ArgumentError, "attachment payload must include path or attachment_id"
      end
    end

    def native_delivery_attachment?(attachment)
      return true unless attachment["attachment_id"].present?

      Attachments::CreateForMessage.native_delivery?(
        attachment: attachment_record(attachment),
        descriptor: attachment
      )
    end

    def signed_link_text(attachment, index)
      lines = []
      lines << payload["text"] if index.zero? && !preview_update? && payload["text"].present?
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

    def mark_delivered!(response)
      responses = response.is_a?(Array) ? response : [response]
      keys = responses.filter_map { |item| extract_external_message_key(item) }
      delivery_attributes = {
        delivery_state: "delivered"
      }
      if keys.present?
        delivered_external_message_keys.concat(keys)
        delivery_attributes[:external_message_key] = keys.first
        if keys.many?
          delivery_attributes[:payload] = payload.merge(
            "delivered_external_message_keys" => keys
          )
        end
      end

      @channel_delivery.update!(delivery_attributes)
    end

    def extract_external_message_key(response)
      return unless response.is_a?(Hash) && response["message_id"].present?

      external_message_key(
        chat_id: response.dig("chat", "id") || chat_id,
        message_id: response.fetch("message_id")
      )
    end

    def track_response!(response)
      key = extract_external_message_key(response)
      delivered_external_message_keys << key if key.present? && !delivered_external_message_keys.include?(key)
      response
    end

    def attachment_caption(index)
      return nil if preview_update?
      return nil unless index.zero?

      payload["text"]
    end

    def external_message_key(chat_id:, message_id:)
      "telegram:chat:#{chat_id}:message:#{message_id}"
    end

    def chat_id
      Integer(@channel_delivery.channel_session.peer_id, 10)
    rescue ArgumentError, TypeError
      @channel_delivery.channel_session.peer_id
    end

    def reply_to_message_id
      key = @channel_delivery.reply_to_external_message_key.to_s
      match = key.match(/\Atelegram:chat:[^:]+:message:(\d+)\z/)
      match && match[1].to_i
    end

    def public_url_options
      Rails.application.routes.default_url_options.presence ||
        ActionMailer::Base.default_url_options
    end
  end
end
