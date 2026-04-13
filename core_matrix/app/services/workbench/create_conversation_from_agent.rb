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

    def initialize(user:, agent:, content:, workspace_id: nil, selector: nil, execution_runtime: nil)
      @user = user
      @agent = agent
      @content = content
      @workspace_id = workspace_id
      @selector = selector
      @execution_runtime = execution_runtime
    end

    def call
      UserAgentBindings::Enable.call(user: @user, agent: @agent)
      workspace = resolve_workspace
      conversation = nil
      turn = nil

      ApplicationRecord.transaction do
        conversation = Conversations::CreateRoot.call(
          workspace: workspace,
          agent: @agent,
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

      Result.new(
        workspace: workspace,
        conversation: conversation,
        turn: turn,
        message: turn.selected_input_message
      )
    end

    private

    def resolve_workspace
      return Workspaces::MaterializeDefault.call(user: @user, agent: @agent) if @workspace_id.blank?

      Workspace.find_by!(
        public_id: @workspace_id,
        installation: @user.installation,
        user: @user,
        agent: @agent
      )
    end

    def enqueue_materialization(turn)
      Turns::MaterializeAndDispatchJob.perform_later(turn.public_id)
    rescue StandardError => error
      Rails.logger.warn("turn workflow bootstrap enqueue failed for #{turn.public_id}: #{error.class}: #{error.message}")
    end
  end
end
