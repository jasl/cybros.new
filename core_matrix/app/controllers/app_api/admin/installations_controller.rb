module AppAPI
  module Admin
    class InstallationsController < BaseController
      def show
        render_method_response(
          method_id: "admin_installation_show",
          installation: AppSurface::Queries::Admin::InstallationOverview.call(
            installation: current_installation
          )
        )
      end
    end
  end
end
