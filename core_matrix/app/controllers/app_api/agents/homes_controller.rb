module AppAPI
  module Agents
    class HomesController < AppAPI::Agents::BaseController
      def show
        home = AppSurface::Queries::AgentHome.call(user: current_user, agent: @agent)

        render_method_response(
          method_id: "agent_home_show",
          agent: AppSurface::Presenters::AgentPresenter.call(agent: home.agent),
          default_workspace_ref: serialize_default_workspace_ref(home.default_workspace_ref),
          workspaces: home.workspaces.map { |workspace| AppSurface::Presenters::WorkspacePresenter.call(workspace: workspace) }
        )
      end

      private

      def serialize_default_workspace_ref(reference)
        {
          "state" => reference.state,
          "workspace_id" => reference.workspace_id,
          "agent_id" => reference.agent_id,
          "user_id" => reference.user_id,
          "name" => reference.name,
          "privacy" => reference.privacy,
          "default_execution_runtime_id" => reference.default_execution_runtime_id,
        }.compact
      end
    end
  end
end
