module ConversationExports
  class BuildManifest
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, conversation_payload:)
      @conversation = conversation
      @conversation_payload = conversation_payload
    end

    def call
      {
        "bundle_kind" => @conversation_payload.fetch("bundle_kind"),
        "bundle_version" => @conversation_payload.fetch("bundle_version"),
        "exported_at" => Time.current.iso8601(6),
        "conversation_public_id" => @conversation.public_id,
        "title" => @conversation_payload.dig("conversation", "title"),
        "summary" => @conversation_payload.dig("conversation", "summary"),
        "title_source" => @conversation_payload.dig("conversation", "title_source"),
        "summary_source" => @conversation_payload.dig("conversation", "summary_source"),
        "message_count" => @conversation_payload.fetch("messages").length,
        "attachment_count" => file_entries.length,
        "files" => file_entries,
        "checksums" => {},
        "generator" => {
          "product" => "core_matrix",
          "format" => "conversation_export_bundle",
        },
      }
    end

    private

    def file_entries
      @file_entries ||= @conversation_payload.fetch("messages").flat_map do |message|
        message.fetch("attachments").map do |attachment|
          {
            "kind" => attachment.fetch("kind"),
            "message_public_id" => attachment.fetch("message_public_id"),
            "filename" => attachment.fetch("filename"),
            "mime_type" => attachment.fetch("mime_type"),
            "byte_size" => attachment.fetch("byte_size"),
            "sha256" => attachment.fetch("sha256"),
            "relative_path" => attachment.fetch("relative_path"),
          }
        end
      end
    end
  end
end
