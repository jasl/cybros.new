module Conversations
  module Metadata
    class Regenerate
      FIELDS = %w[title summary].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(conversation:, field:, generator: nil, occurred_at: Time.current)
        @conversation = conversation
        @field = field.to_s
        @generator = generator || method(:noop_generator)
        @occurred_at = occurred_at
      end

      def call
        ApplicationRecord.transaction do
          Conversations::WithConversationEntryLock.call(
            conversation: @conversation,
            record: @conversation,
            retained_message: "must be retained before regenerating conversation metadata",
            active_message: "must be active before regenerating conversation metadata",
            closing_message: "must not regenerate conversation metadata while close is in progress"
          ) do |conversation|
            validate_field!(conversation)
            unlock_target_field!(conversation)
            invoke_generator!(conversation)
            conversation
          end
        end
      end

      private

      def validate_field!(conversation)
        return if FIELDS.include?(@field)

        raise_invalid!(conversation, :field, "must be title or summary")
      end

      def unlock_target_field!(conversation)
        lock_attribute = @field == "title" ? :title_lock_state : :summary_lock_state
        conversation.update!(lock_attribute => "unlocked")
      end

      def invoke_generator!(conversation)
        @generator.call(
          conversation: conversation,
          field: @field,
          occurred_at: @occurred_at
        )
      end

      def noop_generator(conversation:, field:, occurred_at:)
      end

      def raise_invalid!(record, attribute, message)
        record.errors.add(attribute, message)
        raise ActiveRecord::RecordInvalid, record
      end
    end
  end
end
