module AppAPI
  class WorkspacesController < BaseController
    def index
      workspaces = workspace_lookup_scope.order(is_default: :desc, name: :asc, id: :asc).to_a

      render_method_response(
        method_id: "workspace_list",
        workspaces: workspaces.map do |workspace|
          AppSurface::Presenters::WorkspacePresenter.call(workspace: workspace)
        end
      )
    end

    def create
      workspace = AppSurface::Actions::Workspaces::Create.call(
        user: current_user,
        name: params.fetch(:name),
        privacy: params[:privacy],
        is_default: params[:is_default]
      )

      render_method_response(
        method_id: "workspace_create",
        status: :created,
        workspace: AppSurface::Presenters::WorkspacePresenter.call(workspace: workspace)
      )
    end
  end
end
