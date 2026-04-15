module AppAPI
  module Agents
    class HomesController < AppAPI::Agents::BaseController
      def show
        home = AppSurface::Queries::AgentHome.call(user: current_user, agent: @agent)

        render_method_response(
          method_id: "agent_home_show",
          agent: AppSurface::Presenters::AgentPresenter.call(agent: home.agent),
          workspaces: home.workspaces.map do |workspace|
            AppSurface::Presenters::WorkspacePresenter.call(
              workspace: workspace,
              agent_public_id: home.agent.public_id
            )
          end
        )
      end
    end
  end
end
