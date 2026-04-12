module AppAPI
  module Admin
    class OnboardingSessionsController < BaseController
      def index
        render_method_response(
          method_id: "admin_onboarding_session_index",
          onboarding_sessions: AppSurface::Queries::Admin::ListOnboardingSessions.call(
            installation: current_installation
          ).map { |onboarding_session| AppSurface::Presenters::OnboardingSessionPresenter.call(onboarding_session: onboarding_session) }
        )
      end
    end
  end
end
