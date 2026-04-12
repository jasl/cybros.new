module Workbench
  class CreateConversationFromAgent
    Result = Struct.new(
      :user_agent_binding,
      :workspace,
      :conversation,
      :turn,
      :message,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(user:, agent:, content:, workspace_id: nil)
      @user = user
      @agent = agent
      @content = content
      @workspace_id = workspace_id
    end

    def call
      binding = UserAgentBindings::Enable.call(user: @user, agent: @agent).binding
      workspace = resolve_workspace(binding)
      conversation = Conversations::CreateRoot.call(
        workspace: workspace,
        agent: @agent
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: @content,
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )

      Result.new(
        user_agent_binding: binding,
        workspace: workspace,
        conversation: conversation,
        turn: turn,
        message: turn.selected_input_message
      )
    end

    private

    def resolve_workspace(binding)
      return Workspaces::MaterializeDefault.call(user_agent_binding: binding) if @workspace_id.blank?

      Workspace.find_by!(
        public_id: @workspace_id,
        installation: @user.installation,
        user: @user,
        user_agent_binding: binding
      )
    end
  end
end
