module Workbench
  class CreateConversationFromAgent
    Result = Struct.new(
      :workspace,
      :conversation,
      :turn,
      :message,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(user:, workspace_agent:, content:, selector: nil, execution_runtime: nil)
      @user = user
      @workspace_agent = workspace_agent
      @content = content
      @selector = selector
      @execution_runtime = execution_runtime
    end

    def call
      workspace = @workspace_agent.workspace
      conversation = nil
      turn = nil

      ApplicationRecord.transaction do
        conversation = Conversations::CreateRoot.call(
          workspace_agent: @workspace_agent,
          execution_runtime: @execution_runtime
        )
        turn = Turns::AcceptPendingUserTurn.call(
          conversation: conversation,
          content: @content,
          selector_source: @selector.present? ? "app_api" : "conversation",
          selector: @selector,
          execution_runtime: @execution_runtime
        )
      end

      enqueue_materialization(turn)
      enqueue_title_bootstrap(conversation, turn)

      Result.new(
        workspace: workspace,
        conversation: conversation,
        turn: turn,
        message: turn.selected_input_message
      )
    end

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
