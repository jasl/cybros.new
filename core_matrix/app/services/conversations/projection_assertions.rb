module Conversations
  module ProjectionAssertions
    module_function

    def assert_summary_range!(record:, conversation:, start_message:, end_message:)
      return if conversation.blank? || start_message.blank? || end_message.blank?

      projection_message_ids = Conversations::TranscriptProjection.call(conversation: conversation).map(&:id)

      unless projection_message_ids.include?(start_message.id)
        record.errors.add(:start_message, "must be present in the conversation transcript projection")
      end
      unless projection_message_ids.include?(end_message.id)
        record.errors.add(:end_message, "must be present in the conversation transcript projection")
      end

      if record.errors.any?
        raise ActiveRecord::RecordInvalid, record
      end

      start_index = projection_message_ids.index(start_message.id)
      end_index = projection_message_ids.index(end_message.id)
      return if start_index.blank? || end_index.blank?
      return if start_index <= end_index

      record.errors.add(:end_message, "must come after the start message in transcript order")
      raise ActiveRecord::RecordInvalid, record
    end

    def assert_message_in_base_projection!(record:, conversation:, message:, attribute: :message, error_message: "must be present in the conversation transcript projection")
      return if conversation.blank? || message.blank?
      return if Conversations::TranscriptProjection.base_messages_for(conversation: conversation).any? { |candidate| candidate.id == message.id }

      record.errors.add(attribute, error_message)
      raise ActiveRecord::RecordInvalid, record
    end

    def assert_source_message_in_projection!(record:, source_conversation:, source_message:, branch_prefix:)
      return if source_message.blank? || source_conversation.blank?

      if branch_prefix
        Conversations::HistoricalAnchorProjection.call(
          conversation: source_conversation,
          message: source_message
        )
        return
      end

      assert_message_in_base_projection!(
        record: record,
        conversation: source_conversation,
        message: source_message,
        attribute: :source_message,
        error_message: "must be present in the source conversation transcript projection"
      )
    rescue ActiveRecord::RecordNotFound
      record.errors.add(:source_message, "must be present in the source conversation transcript projection")
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
