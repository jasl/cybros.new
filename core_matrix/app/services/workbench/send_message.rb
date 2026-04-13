module Workbench
  class SendMessage
    Result = Struct.new(:conversation, :turn, :message, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:, selector: nil)
      @conversation = conversation
      @content = content
      @selector = selector
    end

    def call
      turn = Turns::AcceptPendingUserTurn.call(
        conversation: @conversation,
        content: @content,
        selector_source: @selector.present? ? "app_api" : "conversation",
        selector: @selector
      )
      enqueue_materialization(turn)
      enqueue_title_bootstrap(@conversation, turn)

      Result.new(
        conversation: @conversation,
        turn: turn,
        message: turn.selected_input_message
      )
    end

    private

    def enqueue_materialization(turn)
      Turns::MaterializeAndDispatchJob.perform_later(turn.public_id)
    rescue StandardError => error
      Rails.logger.warn("turn workflow bootstrap enqueue failed for #{turn.public_id}: #{error.class}: #{error.message}")
    end

    def enqueue_title_bootstrap(conversation, turn)
      Conversations::Metadata::BootstrapTitleJob.perform_later(conversation.public_id, turn.public_id)
    rescue StandardError => error
      Rails.logger.warn("conversation title bootstrap enqueue failed for #{conversation.public_id}/#{turn.public_id}: #{error.class}: #{error.message}")
    end
  end
end
