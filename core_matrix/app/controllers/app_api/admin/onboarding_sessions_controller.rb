module AppAPI
  module Admin
    class OnboardingSessionsController < BaseController
      def create
        result = AppSurface::Actions::Admin::CreateOnboardingSession.call(
          installation: current_installation,
          actor: current_user,
          target_kind: params.fetch(:target_kind),
          agent_key: params[:agent_key],
          display_name: params[:display_name]
        )

        render_method_response(
          method_id: "admin_onboarding_session_create",
          status: :created,
          onboarding_session: AppSurface::Presenters::OnboardingSessionPresenter.call(
            onboarding_session: result.fetch(:onboarding_session)
          ),
          onboarding_token: result.fetch(:onboarding_token)
        )
      end

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
