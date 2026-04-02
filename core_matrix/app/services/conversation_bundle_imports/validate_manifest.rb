require "digest"

module ConversationBundleImports
  class ValidateManifest
    class InvalidBundle < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(parsed_bundle:)
      @parsed_bundle = parsed_bundle
    end

    def call
      invalid!("manifest must be a hash") unless manifest.is_a?(Hash)
      invalid!("conversation payload must be a hash") unless conversation_payload.is_a?(Hash)
      invalid!("unsupported bundle kind") unless manifest["bundle_kind"] == ConversationExports::BuildConversationPayload::BUNDLE_KIND
      invalid!("unsupported bundle version") unless manifest["bundle_version"] == ConversationExports::BuildConversationPayload::BUNDLE_VERSION
      invalid!("conversation payload bundle kind mismatch") unless conversation_payload["bundle_kind"] == manifest["bundle_kind"]
      invalid!("conversation payload bundle version mismatch") unless conversation_payload["bundle_version"] == manifest["bundle_version"]
      invalid!("conversation public id mismatch") unless conversation_payload.dig("conversation", "public_id") == manifest["conversation_public_id"]
      invalid!("message count mismatch") unless attachments_from_payload.size >= 0 && conversation_payload.fetch("messages").size == manifest["message_count"]
      invalid!("attachment count mismatch") unless attachments_from_payload.size == manifest["attachment_count"]
      invalid!("manifest file count mismatch") unless manifest.fetch("files").size == attachments_from_payload.size

      validate_top_level_checksums!
      validate_attachment_entries!

      true
    end

    private

    def manifest
      @parsed_bundle["manifest"]
    end

    def conversation_payload
      @parsed_bundle["conversation_payload"]
    end

    def entries
      @parsed_bundle["entries"] || {}
    end

    def file_bytes
      @parsed_bundle["file_bytes"] || {}
    end

    def attachments_from_payload
      @attachments_from_payload ||= conversation_payload.fetch("messages").flat_map { |message| message.fetch("attachments") }
    end

    def validate_top_level_checksums!
      checksums = manifest.fetch("checksums", {})
      invalid!("missing bundle checksums") if checksums.blank?

      validate_checksum!(
        entry_name: "conversation.json",
        expected: checksums["conversation_json_sha256"]
      )
      validate_checksum!(
        entry_name: "transcript.md",
        expected: checksums["transcript_md_sha256"]
      )
      validate_checksum!(
        entry_name: "conversation.html",
        expected: checksums["conversation_html_sha256"]
      )
    end

    def validate_attachment_entries!
      attachment_lookup = attachments_from_payload.index_by { |entry| entry.fetch("relative_path") }

      manifest.fetch("files").each do |entry|
        relative_path = entry.fetch("relative_path")
        payload_attachment = attachment_lookup[relative_path]

        invalid!("missing payload attachment for #{relative_path}") if payload_attachment.blank?
        validate_attachment_metadata!(manifest_entry: entry, payload_attachment: payload_attachment)
        invalid!("missing file bytes for #{relative_path}") unless file_bytes.key?(relative_path)
        invalid!("attachment sha256 mismatch for #{relative_path}") unless Digest::SHA256.hexdigest(file_bytes.fetch(relative_path)) == entry.fetch("sha256")
      end
    end

    def validate_attachment_metadata!(manifest_entry:, payload_attachment:)
      %w[kind message_public_id filename mime_type byte_size sha256 relative_path].each do |key|
        next if manifest_entry[key] == payload_attachment[key]

        invalid!("attachment metadata mismatch for #{manifest_entry.fetch("relative_path")} at #{key}")
      end
    end

    def validate_checksum!(entry_name:, expected:)
      invalid!("missing checksum for #{entry_name}") if expected.blank?

      actual_bytes = entries[entry_name]
      invalid!("missing #{entry_name}") if actual_bytes.blank?
      invalid!("checksum mismatch for #{entry_name}") unless Digest::SHA256.hexdigest(actual_bytes) == expected
    end

    def invalid!(message)
      raise InvalidBundle, message
    end
  end
end
