module AppAPI
  class WorkspacePoliciesController < BaseController
    def show
      workspace = find_workspace!(params.fetch(:id))

      render_method_response(
        method_id: "workspace_policy_show",
        workspace_id: workspace.public_id,
        workspace_policy: AppSurface::Presenters::WorkspacePolicyPresenter.call(workspace: workspace)
      )
    end

    def update
      workspace = find_workspace!(params.fetch(:id))
      runtime = resolve_default_execution_runtime(workspace)
      WorkspacePolicies::Upsert.call(
        workspace: workspace,
        disabled_capabilities: params.fetch(:disabled_capabilities, []),
        default_execution_runtime: runtime
      )

      render_method_response(
        method_id: "workspace_policy_update",
        workspace_id: workspace.public_id,
        workspace_policy: AppSurface::Presenters::WorkspacePolicyPresenter.call(workspace: workspace.reload)
      )
    rescue ArgumentError => error
      render_method_response(
        method_id: "workspace_policy_update_error",
        status: :unprocessable_entity,
        error: error.message
      )
    end

    private

    def resolve_default_execution_runtime(workspace)
      return :__preserve__ unless params.key?(:default_execution_runtime_id)
      return nil if params[:default_execution_runtime_id].blank?

      ExecutionRuntime.find_by!(
        public_id: params.fetch(:default_execution_runtime_id),
        installation_id: workspace.installation_id
      )
    end
  end
end
