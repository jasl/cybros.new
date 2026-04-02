require "json"
require "tempfile"
require "zip"

module ConversationExports
  class WriteZipBundle
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      conversation_payload = BuildConversationPayload.call(conversation: @conversation)
      transcript_markdown = RenderTranscriptMarkdown.call(conversation_payload: conversation_payload)
      conversation_html = RenderTranscriptHtml.call(conversation_payload: conversation_payload)
      manifest = BuildManifest.call(
        conversation: @conversation,
        conversation_payload: conversation_payload
      ).merge(
        "checksums" => {
          "conversation_json_sha256" => Digest::SHA256.hexdigest(JSON.pretty_generate(conversation_payload)),
          "transcript_md_sha256" => Digest::SHA256.hexdigest(transcript_markdown),
          "conversation_html_sha256" => Digest::SHA256.hexdigest(conversation_html),
        }
      )

      tempfile = Tempfile.new(["conversation-export-#{@conversation.public_id}", ".zip"])
      tempfile.binmode

      Zip::OutputStream.open(tempfile.path) do |zip|
        zip.put_next_entry("manifest.json")
        zip.write(JSON.pretty_generate(manifest))

        zip.put_next_entry("conversation.json")
        zip.write(JSON.pretty_generate(conversation_payload))

        zip.put_next_entry("transcript.md")
        zip.write(transcript_markdown)

        zip.put_next_entry("conversation.html")
        zip.write(conversation_html)

        attachment_entries(conversation_payload).each do |entry|
          zip.put_next_entry(entry.fetch("relative_path"))
          zip.write(entry.fetch("bytes"))
        end
      end

      tempfile.rewind

      {
        "io" => tempfile,
        "filename" => "conversation-export-#{@conversation.public_id}.zip",
        "content_type" => "application/zip",
        "manifest" => manifest,
        "conversation_payload" => conversation_payload,
      }
    end

    private

    def attachment_entries(conversation_payload)
      conversation_payload.fetch("messages").flat_map do |message|
        message.fetch("attachments").map do |attachment|
          record = MessageAttachment.find_by_public_id!(attachment.fetch("attachment_public_id"))
          {
            "relative_path" => attachment.fetch("relative_path"),
            "bytes" => record.file.download,
          }
        end
      end
    end
  end
end
