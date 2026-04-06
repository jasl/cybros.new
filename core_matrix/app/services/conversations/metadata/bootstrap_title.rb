module Conversations
  module Metadata
    class BootstrapTitle
      MAX_TITLE_LENGTH = 80
      UNTITLED_TITLE = "Untitled conversation"
      SENTENCE_END_PATTERN = /[.!?。！？]/

      def self.call(...)
        new(...).call
      end

      def initialize(conversation:, message:, occurred_at: Time.current)
        @conversation = conversation
        @message = message
        @occurred_at = occurred_at
      end

      def call
        return @conversation unless @message.user?
        return @conversation unless @conversation.title.blank?
        return @conversation if @conversation.title_locked?

        @conversation.update!(
          title: bootstrapped_title,
          title_source: "bootstrap",
          title_updated_at: @occurred_at
        )

        @conversation
      end

      private

      def bootstrapped_title
        first_line = normalized_first_line
        return UNTITLED_TITLE if first_line.blank?

        first_sentence_or_line(first_line).truncate(MAX_TITLE_LENGTH)
      end

      def normalized_first_line
        normalized = @message.content.to_s.tr("\r", "").strip
        return "" if normalized.blank?

        normalized.lines.first.to_s.squish
      end

      def first_sentence_or_line(line)
        match = line.match(/\A(.+?#{SENTENCE_END_PATTERN})(?:\s|$)/)
        match ? match[1] : line
      end
    end
  end
end
