module AppAPI
  module Admin
    class BaseController < AppAPI::BaseController
      before_action :authorize_admin!

      private

      def current_installation
        current_user.installation
      end

      def authorize_admin!
        return if AppSurface::Policies::AdminAccess.call(
          user: current_user,
          installation: current_installation
        )

        render json: { error: "admin access is required" }, status: :forbidden
      end
    end
  end
end
