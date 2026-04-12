module AppAPI
  class ConversationsController < BaseController
    def create
      execution_runtime = resolve_initial_execution_runtime
      agent = find_launchable_agent!(
        params.fetch(:agent_id),
        execution_runtime: execution_runtime || AppSurface::Policies::AgentLaunchability::DEFAULT_RUNTIME
      )
      result = Workbench::CreateConversationFromAgent.call(
        user: current_user,
        agent: agent,
        workspace_id: params[:workspace_id],
        content: params.fetch(:content),
        selector: params[:selector],
        execution_runtime: execution_runtime
      )

      render_method_response(
        method_id: "conversation_create",
        status: :created,
        agent_id: agent.public_id,
        workspace: AppSurface::Presenters::WorkspacePresenter.call(workspace: result.workspace),
        conversation: AppSurface::Presenters::ConversationPresenter.call(conversation: result.conversation),
        turn_id: result.turn.public_id,
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
