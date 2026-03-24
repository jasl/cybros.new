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
        overlay = ConversationMessageVisibility.find_or_initialize_by(
          installation: @conversation.installation,
          conversation: @conversation,
          message: @message
        )

        overlay.hidden = @hidden unless @hidden.nil?
        overlay.excluded_from_context = @excluded_from_context unless @excluded_from_context.nil?

        if !overlay.hidden? && !overlay.excluded_from_context?
          overlay.destroy! if overlay.persisted?
          next nil
        end

        overlay.save!
        overlay
      end
    end
  end
end
