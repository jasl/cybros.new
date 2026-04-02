module ConversationExports
  class RenderTranscriptMarkdown
    def self.call(...)
      new(...).call
    end

    def initialize(conversation_payload:)
      @conversation_payload = conversation_payload
    end

    def call
      lines = []
      lines << "# #{@conversation_payload.dig("conversation", "original_title")}"
      lines << ""

      @conversation_payload.fetch("messages").each do |message|
        lines << "## #{message.fetch("role")} #{message.fetch("slot")}"
        lines << ""
        lines << message.fetch("content")
        lines << ""

        attachments = message.fetch("attachments")
        next if attachments.empty?

        lines << "Attachments:"
        attachments.each do |attachment|
          lines << "- #{attachment.fetch("filename")} (#{attachment.fetch("mime_type")})"
        end
        lines << ""
      end

      lines.join("\n")
    end
  end
end
