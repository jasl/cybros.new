module AppAPI
  module Agents
    class WorkspacesController < AppAPI::Agents::BaseController
      def index
        home = AppSurface::Queries::AgentHome.call(user: current_user, agent: @agent)

        render_method_response(
          method_id: "agent_workspace_list",
          agent_id: @agent.public_id,
          workspaces: home.workspaces.map do |workspace|
            AppSurface::Presenters::WorkspacePresenter.call(
              workspace: workspace,
              agent_public_id: @agent.public_id
            )
          end
        )
      end
    end
  end
end
