module Conversations
  module Metadata
    class AgentUpdate
      UNSET = Object.new

      def self.call(...)
        new(...).call
      end

      def initialize(conversation:, title: UNSET, summary: UNSET, occurred_at: Time.current)
        @conversation = conversation
        @title = title
        @summary = summary
        @occurred_at = occurred_at
      end

      def call
        ApplicationRecord.transaction do
          Conversations::WithConversationEntryLock.call(
            conversation: @conversation,
            record: @conversation,
            retained_message: "must be retained before updating conversation metadata",
            active_message: "must be active before updating conversation metadata",
            closing_message: "must not update conversation metadata while close is in progress"
          ) do |conversation|
            raise_missing_edit!(conversation) unless title_provided? || summary_provided?

            reject_locked_fields!(conversation)
            conversation.update!(update_attributes)
            conversation
          end
        end
      end

      private

      def title_provided?
        @title != UNSET
      end

      def summary_provided?
        @summary != UNSET
      end

      def reject_locked_fields!(conversation)
        raise_invalid!(conversation, :title, "is locked by user") if title_provided? && conversation.title_locked?
        raise_invalid!(conversation, :summary, "is locked by user") if summary_provided? && conversation.summary_locked?
      end

      def update_attributes
        attributes = {}

        if title_provided?
          attributes[:title] = normalize_value!(:title, @title)
          attributes[:title_source] = "agent"
          attributes[:title_updated_at] = @occurred_at
        end

        if summary_provided?
          attributes[:summary] = normalize_value!(:summary, @summary)
          attributes[:summary_source] = "agent"
          attributes[:summary_updated_at] = @occurred_at
        end

        attributes
      end

      def normalize_value!(attribute, value)
        return value if value.nil? || value.is_a?(String)

        raise_invalid!(@conversation, attribute, "must be a string")
      end

      def raise_missing_edit!(conversation)
        raise_invalid!(conversation, :base, "must include title and/or summary")
      end

      def raise_invalid!(record, attribute, message)
        record.errors.add(attribute, message)
        raise ActiveRecord::RecordInvalid, record
      end
    end
  end
end
