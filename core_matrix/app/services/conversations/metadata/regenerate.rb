module Conversations
  module Metadata
    class Regenerate
      FIELDS = %w[title summary].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(conversation:, field:, occurred_at: Time.current)
        @conversation = conversation
        @field = field.to_s
        @occurred_at = occurred_at
      end

      def call
        baseline = capture_baseline!
        generated_content = generate_content!
        persist_generated_content!(generated_content, baseline)
      rescue ActiveRecord::RecordInvalid => error
        restoreable_errors = error.record.errors.messages.deep_dup
        raise_invalid_record!(restoreable_errors)
      end

      private

      def capture_baseline!
        Conversations::WithConversationEntryLock.call(
          conversation: @conversation,
          record: @conversation,
          retained_message: "must be retained before regenerating conversation metadata",
          active_message: "must be active before regenerating conversation metadata",
          closing_message: "must not regenerate conversation metadata while close is in progress"
        ) do |conversation|
          validate_field!(conversation)
          field_state_snapshot_for(conversation)
        end
      end

      def validate_field!(conversation)
        return if FIELDS.include?(@field)

        raise_invalid!(conversation, :field, "must be title or summary")
      end

      def generate_content!
        Conversations::Metadata::GenerateField.call(
          conversation: @conversation,
          field: @field,
          occurred_at: @occurred_at,
          persist: false
        )
      end

      def persist_generated_content!(generated_content, baseline)
        Conversations::WithConversationEntryLock.call(
          conversation: @conversation,
          record: @conversation,
          retained_message: "must be retained before regenerating conversation metadata",
          active_message: "must be active before regenerating conversation metadata",
          closing_message: "must not regenerate conversation metadata while close is in progress"
        ) do |conversation|
          validate_field!(conversation)
          ensure_target_field_matches_baseline!(conversation, baseline)
          update_generated_field!(conversation, generated_content)
          conversation
        end
      end

      def ensure_target_field_matches_baseline!(conversation, baseline)
        return if field_state_snapshot_for(conversation) == baseline

        raise_invalid!(conversation, @field, "changed while regeneration was in progress")
      end

      def update_generated_field!(conversation, generated_content)
        case @field
        when "title"
          conversation.update!(
            title: generated_content,
            title_source: "generated",
            title_updated_at: @occurred_at,
            title_lock_state: "unlocked"
          )
        when "summary"
          conversation.update!(
            summary: generated_content,
            summary_source: "generated",
            summary_updated_at: @occurred_at,
            summary_lock_state: "unlocked"
          )
        else
          raise_invalid!(conversation, :field, "must be title or summary")
        end
      end

      def field_state_snapshot_for(conversation)
        {
          value: field_value_for(conversation),
          source: field_source_for(conversation),
          updated_at: field_updated_at_for(conversation),
          lock_state: field_lock_state_for(conversation),
        }
      end

      def field_value_for(conversation)
        @field == "title" ? conversation.title : conversation.summary
      end

      def field_source_for(conversation)
        @field == "title" ? conversation.title_source : conversation.summary_source
      end

      def field_updated_at_for(conversation)
        @field == "title" ? conversation.title_updated_at : conversation.summary_updated_at
      end

      def field_lock_state_for(conversation)
        @field == "title" ? conversation.title_lock_state : conversation.summary_lock_state
      end

      def raise_invalid_record!(errors_by_attribute)
        errors_by_attribute.each do |attribute, messages|
          Array(messages).each { |message| @conversation.errors.add(attribute, message) }
        end

        raise ActiveRecord::RecordInvalid, @conversation
      end

      def raise_invalid!(record, attribute, message)
        record.errors.add(attribute, message)
        raise ActiveRecord::RecordInvalid, record
      end
    end
  end
end
