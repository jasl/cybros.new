module ClawBotSDK
  module Weixin
    class NormalizeMessage
      TEXT_TYPE = 1
      IMAGE_TYPE = 2
      VOICE_TYPE = 3
      FILE_TYPE = 4
      VIDEO_TYPE = 5

      MODALITY_BY_TYPE = {
        IMAGE_TYPE => "image",
        VOICE_TYPE => "audio",
        FILE_TYPE => "file",
        VIDEO_TYPE => "video"
      }.freeze

      def self.call(...)
        new(...).call
      end

      def initialize(message:, ingress_binding:, channel_connector:)
        @message = message.deep_stringify_keys
        @ingress_binding = ingress_binding
        @channel_connector = channel_connector
      end

      def call
        IngressAPI::Envelope.new(
          platform: "weixin",
          driver: @channel_connector.driver,
          ingress_binding_public_id: @ingress_binding.public_id,
          channel_connector_public_id: @channel_connector.public_id,
          external_event_key: "weixin:update:#{message_id}",
          external_message_key: "weixin:peer:#{from_user_id}:message:#{message_id}",
          peer_kind: "dm",
          peer_id: from_user_id,
          thread_key: nil,
          external_sender_id: from_user_id,
          sender_snapshot: { "id" => from_user_id },
          text: normalized_text,
          attachments: attachment_descriptors,
          reply_to_external_message_key: nil,
          quoted_external_message_key: nil,
          quoted_text: nil,
          quoted_sender_label: nil,
          quoted_attachment_refs: [],
          occurred_at: Time.zone.at(create_time_ms / 1000.0),
          transport_metadata: {
            "context_token" => @message["context_token"],
            "session_id" => @message["session_id"],
            "group_id" => @message["group_id"]
          }.compact,
          raw_payload: @message
        )
      end

      private

      def item_list
        @item_list ||= Array(@message["item_list"]).map(&:deep_stringify_keys)
      end

      def message_id
        @message.fetch("message_id").to_s
      end

      def from_user_id
        @message.fetch("from_user_id").to_s
      end

      def create_time_ms
        @message.fetch("create_time_ms", Time.current.to_f * 1000).to_i
      end

      def normalized_text
        text_item = item_list.find { |item| item["type"].to_i == TEXT_TYPE }
        voice_text = item_list.find { |item| item["type"].to_i == VOICE_TYPE && item.dig("voice_item", "text").present? }

        text_item&.dig("text_item", "text").presence ||
          voice_text&.dig("voice_item", "text").presence ||
          synthesized_attachment_text
      end

      def synthesized_attachment_text
        return nil if attachment_descriptors.empty?

        "User sent #{attachment_descriptors.length} attachment#{'s' if attachment_descriptors.length != 1}."
      end

      def attachment_descriptors
        item_list.filter_map do |item|
          modality = MODALITY_BY_TYPE[item["type"].to_i]
          next if modality.blank?

          {
            "message_item_id" => item["msg_id"],
            "modality" => modality,
            "url" => item.dig("image_item", "url"),
            "content_type" => content_type_for(modality),
            "filename" => item.dig("file_item", "file_name")
          }.compact
        end
      end

      def content_type_for(modality)
        case modality
        when "image" then "image/jpeg"
        when "audio" then "audio/wav"
        when "video" then "video/mp4"
        else "application/octet-stream"
        end
      end
    end
  end
end
