module ConversationSummaries
  class CreateSegment
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, start_message:, end_message:, content:, supersedes: nil)
      @conversation = conversation
      @start_message = start_message
      @end_message = end_message
      @content = content
      @supersedes = supersedes
    end

    def call
      ApplicationRecord.transaction do
        segment = ConversationSummarySegment.create!(
          installation: @conversation.installation,
          conversation: @conversation,
          start_message: @start_message,
          end_message: @end_message,
          content: @content
        )

        @supersedes&.update!(superseded_by: segment)
        segment
      end
    end
  end
end
