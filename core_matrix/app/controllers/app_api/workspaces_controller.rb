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
  end
end
