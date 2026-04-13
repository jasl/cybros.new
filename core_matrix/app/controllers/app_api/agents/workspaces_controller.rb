module AppAPI
  module Agents
    class WorkspacesController < AppAPI::Agents::BaseController
      def index
        home = AppSurface::Queries::AgentHome.call(user: current_user, agent: @agent)

        render_method_response(
          method_id: "agent_workspace_list",
          agent_id: @agent.public_id,
          default_workspace_ref: serialize_default_workspace_ref(home.default_workspace_ref),
          workspaces: home.workspaces.map do |workspace|
            AppSurface::Presenters::WorkspacePresenter.call(
              workspace: workspace,
              agent_public_id: @agent.public_id
            )
          end
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
