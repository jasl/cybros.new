module Messages
  class UpdateVisibility
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, message:, hidden: nil, excluded_from_context: nil)
      @conversation = conversation
      @message = message
      @hidden = hidden
      @excluded_from_context = excluded_from_context
    end

    def call
      raise ArgumentError, "at least one visibility attribute must be provided" if @hidden.nil? && @excluded_from_context.nil?
      raise ArgumentError, "conversation and message must belong to the same installation" unless @conversation.installation_id == @message.installation_id

      ApplicationRecord.transaction do
        Conversations::WithMutableStateLock.call(
          conversation: @conversation,
          record: @conversation,
          retained_message: "must be retained before updating message visibility",
          active_message: "must be active before updating message visibility",
          closing_message: "must not update message visibility while close is in progress"
        ) do |conversation|
          overlay = ConversationMessageVisibility.find_or_initialize_by(
            installation: conversation.installation,
            conversation: conversation,
            message: @message
          )

          overlay.hidden = @hidden unless @hidden.nil?
          overlay.excluded_from_context = @excluded_from_context unless @excluded_from_context.nil?

          Conversations::ProjectionAssertions.assert_message_in_base_projection!(
            record: overlay,
            conversation: conversation,
            message: @message
          )

          if @message.fork_point? &&
              (overlay.hidden? || overlay.excluded_from_context?)
            raise_invalid!(@message, :base, "fork-point messages cannot be hidden or excluded from context")
          end

          if !overlay.hidden? && !overlay.excluded_from_context?
            overlay.destroy! if overlay.persisted?
            next nil
          end

          overlay.save!
          overlay
        end
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
