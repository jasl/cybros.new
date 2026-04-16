module AppAPI
  class BootstrapController < AppAPI::BaseController
    skip_before_action :authenticate_session!

    rescue_from Installations::BootstrapFirstAdmin::AlreadyBootstrapped do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    def status
      installation = Installation.order(:id).first

      render_method_response(
        method_id: "bootstrap_status",
        bootstrap_state: installation.present? ? "bootstrapped" : "unbootstrapped",
        installation: presented_installation(installation)
      )
    end

    def create
      result = AppSurface::Actions::Bootstrap::IssueFirstAdmin.call(
        name: params.fetch(:name),
        email: params.fetch(:email),
        password: params.fetch(:password),
        password_confirmation: params.fetch(:password_confirmation),
        display_name: params.fetch(:display_name)
      )

      render_method_response(
        method_id: "bootstrap_create",
        status: :created,
        **AppSurface::Presenters::AuthenticatedSessionPresenter.call(
          session: result.fetch(:session),
          plaintext_token: result.fetch(:session_token),
          workspace: result[:workspace],
          workspace_agent: result[:workspace_agent]
        )
      )
    end

    private

    def current_installation_id
      current_user&.installation_id
    end

    def presented_installation(installation)
      return nil if installation.blank?

      {
        "name" => installation.name,
        "bootstrap_state" => installation.bootstrap_state,
      }
    end
  end
end
