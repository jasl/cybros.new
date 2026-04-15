module IngressAPI
  module Telegram
    class NormalizeUpdate
      def self.call(...)
        new(...).call
      end

      def initialize(update_payload:, ingress_binding:, channel_connector:)
        @update_payload = update_payload.deep_stringify_keys
        @ingress_binding = ingress_binding
        @channel_connector = channel_connector
      end

      def call
        current_attachment_descriptors = attachment_descriptors_for(message)
        quoted_attachment_descriptors = attachment_descriptors_for(reply_message)

        IngressAPI::Envelope.new(
          platform: "telegram",
          driver: @channel_connector.driver,
          ingress_binding_public_id: @ingress_binding.public_id,
          channel_connector_public_id: @channel_connector.public_id,
          external_event_key: "telegram:update:#{update_id}",
          external_message_key: external_message_key(message.fetch("message_id")),
          peer_kind: peer_kind,
          peer_id: chat.fetch("id").to_s,
          thread_key: message["message_thread_id"]&.to_s,
          external_sender_id: from.fetch("id").to_s,
          sender_snapshot: sender_snapshot,
          text: normalized_text_for(message, current_attachment_descriptors),
          attachments: current_attachment_descriptors,
          reply_to_external_message_key: reply_to_external_message_key,
          quoted_external_message_key: quoted_external_message_key,
          quoted_text: quoted_text_for(quoted_attachment_descriptors),
          quoted_sender_label: sender_label_for(reply_from),
          quoted_attachment_refs: quoted_attachment_descriptors,
          occurred_at: Time.zone.at(message.fetch("date")),
          transport_metadata: {
            "telegram_update_id" => update_id,
            "telegram_chat_id" => chat.fetch("id").to_s,
            "telegram_message_id" => message.fetch("message_id").to_s,
          }.compact,
          raw_payload: @update_payload
        )
      end

      private

      def update_id
        @update_id ||= @update_payload.fetch("update_id")
      end

      def message
        @message ||= @update_payload.fetch("message")
      end

      def chat
        @chat ||= message.fetch("chat")
      end

      def from
        @from ||= message.fetch("from")
      end

      def peer_kind
        chat.fetch("type") == "private" ? "dm" : "group"
      end

      def sender_snapshot
        {
          "id" => from.fetch("id").to_s,
          "username" => from["username"],
          "first_name" => from["first_name"],
          "last_name" => from["last_name"],
        }.compact
      end

      def normalized_text_for(message_payload, descriptors)
        return if message_payload.blank?

        message_payload["text"].presence ||
          message_payload["caption"].presence ||
          synthesized_media_text_for(descriptors)
      end

      def synthesized_media_text_for(descriptors)
        return nil if descriptors.empty?

        "User sent #{descriptors.length} attachment#{"s" if descriptors.length != 1}."
      end

      def attachment_descriptors
        @attachment_descriptors ||= attachment_descriptors_for(message)
      end

      def attachment_descriptors_for(message_payload)
        return [] if message_payload.blank?

        attachments = []

        if message_payload["photo"].present?
          photo = Array(message_payload["photo"]).max_by { |item| item["file_size"].to_i }
          attachments << {
            "file_id" => photo.fetch("file_id"),
            "file_unique_id" => photo["file_unique_id"],
            "modality" => "image",
            "byte_size" => photo["file_size"],
            "width" => photo["width"],
            "height" => photo["height"],
          }.compact
        end

        if message_payload["document"].present?
          document = message_payload.fetch("document")
          attachments << {
            "file_id" => document.fetch("file_id"),
            "file_unique_id" => document["file_unique_id"],
            "modality" => "file",
            "filename" => document["file_name"],
            "content_type" => document["mime_type"],
            "byte_size" => document["file_size"],
          }.compact
        end

        attachments
      end

      def reply_to_external_message_key
        reply_message_id = reply_message&.fetch("message_id", nil)
        return if reply_message_id.blank?

        external_message_key(reply_message_id)
      end

      def quoted_external_message_key
        reply_to_external_message_key
      end

      def quoted_text_for(quoted_attachment_descriptors)
        quote_payload&.dig("text").presence ||
          normalized_text_for(reply_message, quoted_attachment_descriptors)
      end

      def reply_message
        @reply_message ||= message["reply_to_message"]&.deep_stringify_keys
      end

      def quote_payload
        @quote_payload ||= message["quote"]&.deep_stringify_keys
      end

      def reply_from
        @reply_from ||= reply_message&.dig("from")&.deep_stringify_keys
      end

      def sender_label_for(sender_payload)
        return if sender_payload.blank?

        [
          sender_payload["first_name"],
          sender_payload["last_name"],
        ].compact.join(" ").presence ||
          sender_payload["username"].presence ||
          sender_payload["id"]&.to_s
      end

      def external_message_key(message_id)
        "telegram:chat:#{chat.fetch("id")}:message:#{message_id}"
      end
    end
  end
end
