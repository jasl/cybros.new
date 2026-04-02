require "digest"

module ConversationExports
  class BuildConversationPayload
    BUNDLE_KIND = "conversation_export".freeze
    BUNDLE_VERSION = "2026-04-02".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      {
        "bundle_kind" => BUNDLE_KIND,
        "bundle_version" => BUNDLE_VERSION,
        "conversation" => conversation_payload,
        "messages" => transcript_messages.map { |message| message_payload(message) },
      }
    end

    private

    def conversation_payload
      {
        "public_id" => @conversation.public_id,
        "kind" => @conversation.kind,
        "purpose" => @conversation.purpose,
        "addressability" => @conversation.addressability,
        "lifecycle_state" => @conversation.lifecycle_state,
        "created_at" => @conversation.created_at&.iso8601(6),
        "updated_at" => @conversation.updated_at&.iso8601(6),
        "original_title" => original_title,
      }.compact
    end

    def message_payload(message)
      {
        "message_public_id" => message.public_id,
        "conversation_public_id" => message.conversation.public_id,
        "turn_public_id" => message.turn.public_id,
        "role" => message.role,
        "slot" => message.slot,
        "variant_index" => message.variant_index,
        "content" => message.content,
        "created_at" => message.created_at&.iso8601(6),
        "updated_at" => message.updated_at&.iso8601(6),
        "attachments" => message.message_attachments.order(:id).map { |attachment| attachment_payload(message, attachment) },
      }.compact
    end

    def attachment_payload(message, attachment)
      {
        "attachment_public_id" => attachment.public_id,
        "message_public_id" => message.public_id,
        "kind" => message.user? ? "user_upload" : "generated_output",
        "filename" => attachment.file.filename.to_s,
        "mime_type" => attachment.file.blob.content_type,
        "byte_size" => attachment.file.blob.byte_size,
        "sha256" => sha256_for(attachment),
        "relative_path" => relative_path_for(attachment),
        "origin_attachment_public_id" => attachment.origin_attachment&.public_id,
        "origin_message_public_id" => attachment.origin_message&.public_id,
      }.compact
    end

    def transcript_messages
      @transcript_messages ||= Conversations::TranscriptProjection.call(conversation: @conversation)
    end

    def original_title
      first_content = transcript_messages.find(&:user?)&.content.to_s.strip
      return "Conversation #{@conversation.public_id}" if first_content.blank?

      first_content.gsub(/\s+/, " ").truncate(80)
    end

    def sha256_for(attachment)
      digest = Digest::SHA256.new
      attachment.file.blob.open do |io|
        while (chunk = io.read(16 * 1024))
          digest.update(chunk)
        end
      end
      digest.hexdigest
    end

    def relative_path_for(attachment)
      filename = attachment.file.filename.to_s.gsub(/[^\w.\-]+/, "_")
      filename = "attachment" if filename.blank?
      "files/#{attachment.public_id}-#{filename}"
    end
  end
end
