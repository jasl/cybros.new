module AppAPI
  class AgentConversationsController < BaseController
    def create
      agent = find_agent!(params.fetch(:agent_id))
      result = Workbench::CreateConversationFromAgent.call(
        user: current_user,
        agent: agent,
        workspace_id: params[:workspace_id],
        content: params.fetch(:content),
        selector: params[:selector]
      )

      render_method_response(
        method_id: "agent_conversation_create",
        status: :created,
        agent_id: agent.public_id,
        workspace: AppSurface::Presenters::WorkspacePresenter.call(workspace: result.workspace),
        conversation: AppSurface::Presenters::ConversationPresenter.call(conversation: result.conversation),
        turn_id: result.turn.public_id,
        message: serialize_message(result.message)
      )
    end
  end
end
