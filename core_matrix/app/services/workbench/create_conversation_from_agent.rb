module Workbench
  class CreateConversationFromAgent
    Result = Struct.new(
      :user_agent_binding,
      :workspace,
      :conversation,
      :turn,
      :workflow_run,
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
      binding = UserAgentBindings::Enable.call(user: @user, agent: @agent).binding
      workspace = resolve_workspace(binding)
      conversation = Conversations::CreateRoot.call(
        workspace: workspace,
        agent: @agent
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: @content,
        execution_runtime: @execution_runtime,
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: "turn_step",
        root_node_type: "turn_step",
        decision_source: "system",
        metadata: {},
        selector_source: @selector.present? ? "app_api" : "conversation",
        selector: @selector
      )
      Workflows::ExecuteRun.call(workflow_run: workflow_run)

      Result.new(
        user_agent_binding: binding,
        workspace: workspace,
        conversation: conversation,
        turn: turn,
        workflow_run: workflow_run,
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
