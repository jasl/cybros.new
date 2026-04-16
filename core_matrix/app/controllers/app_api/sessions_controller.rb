module AppAPI
  class SessionsController < AppAPI::BaseController
    skip_before_action :authenticate_session!, only: :create

    rescue_from AppSurface::Actions::Sessions::Create::InvalidCredentials do |error|
      render json: { error: error.message }, status: :unauthorized
    end

    def show
      render_method_response(
        method_id: "session_show",
        **AppSurface::Presenters::AuthenticatedSessionPresenter.call(session: current_session)
      )
    end

    def create
      result = AppSurface::Actions::Sessions::Create.call(
        email: params.fetch(:email),
        password: params.fetch(:password)
      )

      render_method_response(
        method_id: "session_create",
        status: :created,
        **AppSurface::Presenters::AuthenticatedSessionPresenter.call(
          session: result.fetch(:session),
          plaintext_token: result.fetch(:session_token)
        )
      )
    end

    def destroy
      current_session.revoke!

      render_method_response(
        method_id: "session_destroy",
        **AppSurface::Presenters::AuthenticatedSessionPresenter.call(session: current_session)
      )
    end

    private

    def current_installation_id
      current_user&.installation_id
    end
  end
end
