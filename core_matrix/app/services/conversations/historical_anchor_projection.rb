module Conversations
  class HistoricalAnchorProjection
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, message:)
      @conversation = conversation
      @message = message
    end

    def call
      raise ActiveRecord::RecordNotFound, "historical anchor is missing from the parent conversation history" if @message.blank?

      if @message.conversation_id == @conversation.id
        local_prefix_messages
      else
        projection_prefix_messages
      end
    end

    private

    def projection_prefix_messages
      messages = Conversations::TranscriptProjection.base_messages_for(conversation: @conversation)
      anchor_index = messages.index { |candidate| candidate.id == @message.id }
      raise ActiveRecord::RecordNotFound, "historical anchor is missing from the parent conversation history" unless anchor_index.present?

      prefix_messages_for_anchor(messages, anchor_index:)
    end

    def local_prefix_messages
      raise ActiveRecord::RecordNotFound, "historical anchor is missing from the parent conversation history" unless @message.conversation_id == @conversation.id

      prefix_messages = inherited_transcript_messages
      @conversation.turns.where("sequence < ?", @message.turn.sequence)
        .includes(:selected_input_message, :selected_output_message)
        .order(:sequence)
        .each do |turn|
          prefix_messages.concat([turn.selected_input_message, turn.selected_output_message].compact)
        end

      if @message.input?
        prefix_messages << @message
        return prefix_messages
      end

      source_input_message = @message.source_input_message
      unless source_input_message.present? && source_input_message.turn_id == @message.turn_id
        raise ActiveRecord::RecordNotFound, "historical anchor is missing source input provenance"
      end

      prefix_messages + [source_input_message, @message]
    end

    def inherited_transcript_messages
      return [] if @conversation.parent_conversation.blank?
      return Conversations::TranscriptProjection.base_messages_for(conversation: @conversation.parent_conversation) if @conversation.thread?

      self.class.call(
        conversation: @conversation.parent_conversation,
        message: @conversation.historical_anchor_message
      )
    end

    def prefix_messages_for_anchor(messages, anchor_index:)
      return messages.first(anchor_index) + [@message] if @message.input?

      source_input_message = @message.source_input_message
      source_input_index = messages.index { |candidate| candidate.id == source_input_message&.id }
      if source_input_message.present? &&
          source_input_message.turn_id == @message.turn_id &&
          source_input_index.present?
        return messages.first(source_input_index) + [source_input_message, @message]
      end

      raise ActiveRecord::RecordNotFound, "historical anchor is missing source input provenance"
    end
  end
end
