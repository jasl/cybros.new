require "erb"

module ConversationExports
  class RenderTranscriptHtml
    def self.call(...)
      new(...).call
    end

    def initialize(conversation_payload:)
      @conversation_payload = conversation_payload
    end

    def call
      body = @conversation_payload.fetch("messages").map do |message|
        attachments = message.fetch("attachments").map do |attachment|
          "<li>#{ERB::Util.html_escape(attachment.fetch("filename"))} (#{ERB::Util.html_escape(attachment.fetch("mime_type"))})</li>"
        end.join

        <<~HTML
          <section class="message">
            <h2>#{ERB::Util.html_escape(message.fetch("role"))} #{ERB::Util.html_escape(message.fetch("slot"))}</h2>
            <pre>#{ERB::Util.html_escape(message.fetch("content"))}</pre>
            #{attachments.present? ? "<ul>#{attachments}</ul>" : ""}
          </section>
        HTML
      end.join("\n")

      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <title>#{ERB::Util.html_escape(@conversation_payload.dig("conversation", "original_title"))}</title>
          </head>
          <body>
            <main>
              <h1>#{ERB::Util.html_escape(@conversation_payload.dig("conversation", "original_title"))}</h1>
              #{body}
            </main>
          </body>
        </html>
      HTML
    end
  end
end
