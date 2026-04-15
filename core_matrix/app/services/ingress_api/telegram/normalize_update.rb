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
          text: normalized_text,
          attachments: attachment_descriptors,
          reply_to_external_message_key: reply_to_external_message_key,
          quoted_external_message_key: nil,
          quoted_text: nil,
          quoted_sender_label: nil,
          quoted_attachment_refs: [],
          occurred_at: Time.zone.at(message.fetch("date")),
          transport_metadata: {
            "telegram_update_id" => update_id,
            "telegram_chat_id" => chat.fetch("id").to_s,
            "telegram_message_id" => message.fetch("message_id").to_s
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
          "last_name" => from["last_name"]
        }.compact
      end

      def normalized_text
        message["text"].presence ||
          message["caption"].presence ||
          synthesized_media_text
      end

      def synthesized_media_text
        return nil if attachment_descriptors.empty?

        "User sent #{attachment_descriptors.length} attachment#{'s' if attachment_descriptors.length != 1}."
      end

      def attachment_descriptors
        @attachment_descriptors ||= begin
          attachments = []

          if message["photo"].present?
            photo = Array(message["photo"]).max_by { |item| item["file_size"].to_i }
            attachments << {
              "file_id" => photo.fetch("file_id"),
              "file_unique_id" => photo["file_unique_id"],
              "modality" => "image",
              "byte_size" => photo["file_size"],
              "width" => photo["width"],
              "height" => photo["height"]
            }.compact
          end

          if message["document"].present?
            document = message.fetch("document")
            attachments << {
              "file_id" => document.fetch("file_id"),
              "file_unique_id" => document["file_unique_id"],
              "modality" => "file",
              "filename" => document["file_name"],
              "content_type" => document["mime_type"],
              "byte_size" => document["file_size"]
            }.compact
          end

          attachments
        end
      end

      def reply_to_external_message_key
        reply_message_id = message.dig("reply_to_message", "message_id")
        return if reply_message_id.blank?

        external_message_key(reply_message_id)
      end

      def external_message_key(message_id)
        "telegram:chat:#{chat.fetch('id')}:message:#{message_id}"
      end
    end
  end
end
