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
            Conversations::ManagedPolicy.assert_not_managed!(
              conversation: conversation,
              record: conversation,
              message: "must not update conversation metadata while externally managed"
            )

            attributes, rejections = update_plan_for(conversation)
            raise_rejections!(conversation, rejections) if attributes.empty?

            conversation.update!(attributes)
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

      def update_plan_for(conversation)
        attributes = {}
        rejections = {}

        if title_provided?
          title_value, title_rejection = normalize_updatable_value(
            conversation: conversation,
            attribute: :title,
            value: @title
          )
          if title_rejection.present?
            rejections[:title] = title_rejection
          else
            attributes[:title] = title_value
            attributes[:title_source] = "agent"
            attributes[:title_updated_at] = @occurred_at
          end
        end

        if summary_provided?
          summary_value, summary_rejection = normalize_updatable_value(
            conversation: conversation,
            attribute: :summary,
            value: @summary
          )
          if summary_rejection.present?
            rejections[:summary] = summary_rejection
          else
            attributes[:summary] = summary_value
            attributes[:summary_source] = "agent"
            attributes[:summary_updated_at] = @occurred_at
          end
        end

        [attributes, rejections]
      end

      def normalize_updatable_value(conversation:, attribute:, value:)
        return [nil, "is locked by user"] if attribute == :title && conversation.title_locked?
        return [nil, "is locked by user"] if attribute == :summary && conversation.summary_locked?
        return [nil, "must be a string"] unless value.nil? || value.is_a?(String)
        return [nil, "contains internal metadata content"] if internal_metadata_content?(value)

        [value, nil]
      end

      def internal_metadata_content?(value)
        InternalContentGuard.internal_metadata_content?(value)
      end

      def raise_missing_edit!(conversation)
        raise_invalid!(conversation, :base, "must include title and/or summary")
      end

      def raise_rejections!(conversation, rejections)
        rejections.each do |attribute, message|
          conversation.errors.add(attribute, message)
        end
        raise ActiveRecord::RecordInvalid, conversation
      end

      def raise_invalid!(record, attribute, message)
        record.errors.add(attribute, message)
        raise ActiveRecord::RecordInvalid, record
      end
    end
  end
end
