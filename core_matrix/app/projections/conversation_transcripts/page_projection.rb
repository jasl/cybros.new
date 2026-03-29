module ConversationTranscripts
  class PageProjection
    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100

    Result = Struct.new(:messages, :next_cursor, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, cursor: nil, limit: DEFAULT_LIMIT)
      @conversation = conversation
      @cursor = cursor.presence
      @limit = normalize_limit(limit)
    end

    def call
      messages = Conversations::TranscriptProjection.call(conversation: @conversation)
      start_index = cursor_start_index(messages)
      page = messages.drop(start_index).first(@limit)
      has_more = messages[start_index + page.length].present?

      Result.new(
        messages: page,
        next_cursor: has_more ? page.last.public_id : nil
      )
    end

    private

    def normalize_limit(limit)
      normalized = limit.to_i
      return DEFAULT_LIMIT if normalized <= 0

      [normalized, MAX_LIMIT].min
    end

    def cursor_start_index(messages)
      return 0 if @cursor.blank?

      index = messages.index { |message| message.public_id == @cursor.to_s }
      raise ActiveRecord::RecordNotFound, "cursor is not present in the visible transcript" if index.nil?

      index + 1
    end
  end
end
