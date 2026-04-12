module AppAPI
  module Admin
    class ExecutionRuntimesController < BaseController
      def index
        render_method_response(
          method_id: "admin_execution_runtime_index",
          execution_runtimes: AppSurface::Queries::Admin::ListExecutionRuntimes.call(
            installation: current_installation
          ).map { |execution_runtime| AppSurface::Presenters::ExecutionRuntimePresenter.call(execution_runtime: execution_runtime) }
        )
      end
    end
  end
end
