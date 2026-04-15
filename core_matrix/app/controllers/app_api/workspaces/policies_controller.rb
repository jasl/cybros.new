module AppAPI
  module Workspaces
    class PoliciesController < AppAPI::Workspaces::BaseController
      before_action :set_workspace_agent

      def show
        render_method_response(
          method_id: "workspace_policy_show",
          workspace_id: @workspace.public_id,
          workspace_policy: AppSurface::Presenters::WorkspacePolicyPresenter.call(
            workspace: @workspace,
            workspace_agent: @workspace_agent
          )
        )
      end

      def update
        runtime = resolve_default_execution_runtime
        WorkspacePolicies::Upsert.call(
          workspace: @workspace,
          workspace_agent: @workspace_agent,
          disabled_capabilities: params.fetch(:disabled_capabilities, []),
          default_execution_runtime: runtime,
          features: resolve_features
        )

        render_method_response(
          method_id: "workspace_policy_update",
          workspace_id: @workspace.public_id,
          workspace_policy: AppSurface::Presenters::WorkspacePolicyPresenter.call(
            workspace: @workspace.reload,
            workspace_agent: @workspace_agent.reload
          )
        )
      rescue ArgumentError => error
        render_method_response(
          method_id: "workspace_policy_update_error",
          status: :unprocessable_entity,
          error: error.message
        )
      end

      private

      def set_workspace_agent
        @workspace_agent ||= find_workspace_agent!(params.fetch(:workspace_agent_id), workspace: @workspace)
      end

      def resolve_default_execution_runtime
        return :__preserve__ unless params.key?(:default_execution_runtime_id)
        return nil if params[:default_execution_runtime_id].blank?

        find_accessible_execution_runtime!(params.fetch(:default_execution_runtime_id))
      end

      def resolve_features
        return :__preserve__ unless params.key?(:features)

        params[:features]
      end
    end
  end
end
