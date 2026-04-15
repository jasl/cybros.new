module AppAPI
  class ConversationsController < BaseController
    def create
      execution_runtime = resolve_initial_execution_runtime
      workspace_agent = find_launchable_workspace_agent!(
        params.fetch(:workspace_agent_id),
        execution_runtime: execution_runtime || AppSurface::Policies::AgentLaunchability::DEFAULT_RUNTIME
      )
      result = Workbench::CreateConversationFromAgent.call(
        user: current_user,
        workspace_agent: workspace_agent,
        content: params.fetch(:content),
        selector: params[:selector],
        execution_runtime: execution_runtime
      )

      render_method_response(
        method_id: "conversation_create",
        status: :created,
        agent_id: workspace_agent.agent.public_id,
        workspace: AppSurface::Presenters::WorkspacePresenter.call(
          workspace: result.workspace,
          agent_public_id: workspace_agent.agent.public_id,
          workspace_agents: [workspace_agent]
        ),
        conversation: AppSurface::Presenters::ConversationPresenter.call(conversation: result.conversation),
        turn_id: result.turn.public_id,
        execution_status: result.turn.workflow_bootstrap_state,
        accepted_at: result.turn.workflow_bootstrap_requested_at&.iso8601(6),
        request_summary: ConversationSupervision::BuildGoalSummary.call(content: result.message.content),
        message: serialize_message(result.message)
      )
    end

    private

    def resolve_initial_execution_runtime
      return nil if params[:execution_runtime_id].blank?

      find_accessible_execution_runtime!(params.fetch(:execution_runtime_id))
    end
  end
end
