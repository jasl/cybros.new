module AppAPI
  module Admin
    class AgentsController < BaseController
      def index
        render_method_response(
          method_id: "admin_agent_index",
          agents: AppSurface::Queries::Admin::ListAgents.call(
            installation: current_installation
          ).map { |agent| AppSurface::Presenters::AgentPresenter.call(agent: agent) }
        )
      end
    end
  end
end
