module Conversations
  class ValidateHistoricalAnchor
    def self.call(...)
      new(...).call
    end

    def initialize(parent:, kind:, historical_anchor_message_id:, record:)
      @parent = parent
      @kind = kind.to_s
      @historical_anchor_message_id = historical_anchor_message_id
      @record = record
    end

    def call
      return nil unless @parent.present?

      if anchor_required? && @historical_anchor_message_id.blank?
        invalid_record.errors.add(:historical_anchor_message_id, "must exist")
        raise ActiveRecord::RecordInvalid, invalid_record
      end

      return nil if @historical_anchor_message_id.blank?

      anchor_message = Message.find_by(
        id: @historical_anchor_message_id,
        installation_id: @parent.installation_id
      )

      unless anchor_message.present? && @parent.transcript_projection_includes?(anchor_message)
        invalid_record.errors.add(:historical_anchor_message_id, "must belong to the parent conversation history")
        raise ActiveRecord::RecordInvalid, invalid_record
      end

      validate_output_anchor_provenance!(anchor_message)
      anchor_message
    end

    private

    def anchor_required?
      @kind == "branch" || @kind == "checkpoint"
    end

    def invalid_record
      @record || @parent
    end

    def validate_output_anchor_provenance!(anchor_message)
      return unless anchor_message.output?

      source_input_message = anchor_message.source_input_message
      return if source_input_message.present? &&
        source_input_message.turn_id == anchor_message.turn_id &&
        @parent.transcript_projection_includes?(source_input_message)

      invalid_record.errors.add(:historical_anchor_message_id, "must belong to the parent conversation history")
      raise ActiveRecord::RecordInvalid, invalid_record
    end
  end
end
