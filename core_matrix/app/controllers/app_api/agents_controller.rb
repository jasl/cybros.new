module AppAPI
  class AgentsController < BaseController
    def index
      agents = AppSurface::Queries::VisibleAgents.call(user: current_user)

      render_method_response(
        method_id: "agents_index",
        agents: agents.map { |agent| AppSurface::Presenters::AgentPresenter.call(agent: agent) }
      )
    end
  end
end
