module AppAPI
  module Workspaces
    class PoliciesController < AppAPI::Workspaces::BaseController
      def show
        render_method_response(
          method_id: "workspace_policy_show",
          workspace_id: @workspace.public_id,
          workspace_policy: AppSurface::Presenters::WorkspacePolicyPresenter.call(workspace: @workspace)
        )
      end

      def update
        runtime = resolve_default_execution_runtime
        WorkspacePolicies::Upsert.call(
          workspace: @workspace,
          disabled_capabilities: params.fetch(:disabled_capabilities, []),
          default_execution_runtime: runtime
        )

        render_method_response(
          method_id: "workspace_policy_update",
          workspace_id: @workspace.public_id,
          workspace_policy: AppSurface::Presenters::WorkspacePolicyPresenter.call(workspace: @workspace.reload)
        )
      rescue ArgumentError => error
        render_method_response(
          method_id: "workspace_policy_update_error",
          status: :unprocessable_entity,
          error: error.message
        )
      end

      private

      def resolve_default_execution_runtime
        return :__preserve__ unless params.key?(:default_execution_runtime_id)
        return nil if params[:default_execution_runtime_id].blank?

        find_accessible_execution_runtime!(params.fetch(:default_execution_runtime_id))
      end
    end
  end
end
