module ConversationSupervision
  class BuildContextSnippets
    DEFAULT_LIMIT = 8
    EXCERPT_LENGTH = 240
    STOP_WORDS = %w[
      a an and already before for from has have in into is of on or that the this to while with
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, limit: DEFAULT_LIMIT)
      @conversation = conversation
      @limit = limit
    end

    def call
      {
        "message_ids" => messages.map(&:public_id),
        "turn_ids" => messages.filter_map { |message| message.turn&.public_id }.uniq,
        "context_snippets" => messages.filter_map { |message| serialize_snippet(message) },
      }
    end

    private

    def projection
      @projection ||= Conversations::ContextProjection.call(conversation: @conversation)
    end

    def messages
      @messages ||= projection.messages.last(@limit)
    end

    def serialize_snippet(message)
      excerpt = normalized_excerpt(message.content)
      return if excerpt.blank?

      {
        "message_id" => message.public_id,
        "turn_id" => message.turn&.public_id,
        "role" => message.role,
        "slot" => message.slot,
        "excerpt" => excerpt,
        "keywords" => context_keywords(excerpt),
      }.compact
    end

    def normalized_excerpt(content)
      normalized = content.to_s.squish
      return if normalized.blank?

      normalized.truncate(EXCERPT_LENGTH, separator: /\s/)
    end

    def context_keywords(content)
      content.to_s.downcase.scan(/[a-z0-9]+/).uniq - STOP_WORDS
    end
  end
end
