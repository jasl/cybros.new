module AppAPI
  module Admin
    module LLMProviders
      module CodexSubscription
        class AuthorizationsController < AppAPI::Admin::BaseController
          skip_before_action :authenticate_session!, only: :callback
          skip_before_action :verify_cookie_backed_session_csrf!, only: :callback
          skip_before_action :authorize_admin!, only: :callback
          before_action :ensure_codex_subscription_enabled!

          def show
            render_method_response(
              method_id: "admin_codex_subscription_authorization_show",
              authorization: authorization_payload
            )
          end

          def create
            result = ProviderAuthorizationSessions::Issue.call(
              installation: current_installation,
              actor: current_user,
              provider_handle: "codex_subscription",
              redirect_uri: callback_redirect_uri
            )

            render_method_response(
              method_id: "admin_codex_subscription_authorization_create",
              authorization: authorization_payload(
                authorization_session: result.fetch(:authorization_session),
                authorization_url: result.fetch(:authorization_url)
              )
            )
          end

          def destroy
            ApplicationRecord.transaction do
              ProviderAuthorizationSession.where(
                installation: current_installation,
                provider_handle: "codex_subscription",
                status: "pending"
              ).find_each(&:revoke!)
              ProviderCredential.where(
                installation: current_installation,
                provider_handle: "codex_subscription",
                credential_kind: "oauth_codex"
              ).destroy_all
            end

            render_method_response(
              method_id: "admin_codex_subscription_authorization_destroy",
              authorization: authorization_payload
            )
          end

          def callback
            ProviderAuthorizationSessions::CompleteCodexCallback.call(
              state: params.fetch(:state),
              code: params.fetch(:code),
              redirect_uri: callback_redirect_uri
            )

            render plain: "Codex subscription authorization completed. You can return to the app.", status: :ok
          rescue KeyError => error
            render plain: error.message, status: :unprocessable_entity
          rescue ProviderAuthorizationSessions::ResolveFromState::InvalidState,
                 ProviderAuthorizationSessions::ResolveFromState::ExpiredSession,
                 ProviderAuthorizationSessions::ResolveFromState::RevokedSession,
                 ProviderAuthorizationSessions::ResolveFromState::CompletedSession => error
            render plain: error.message, status: :unprocessable_entity
          end

          private

          def ensure_codex_subscription_enabled!
            provider_definition = provider_catalog.provider("codex_subscription")
            raise ActiveRecord::RecordNotFound, "Couldn't find LLM provider" unless provider_definition.fetch(:enabled)
          end

          def provider_catalog
            if current_user.present?
              ProviderCatalog::EffectiveCatalog.new(installation: current_installation)
            else
              ProviderCatalog::EffectiveCatalog.new
            end
          end

          def current_credential
            @current_credential ||= ProviderCredential.find_by(
              installation: current_installation,
              provider_handle: "codex_subscription",
              credential_kind: "oauth_codex"
            )
          end

          def pending_authorization_session
            @pending_authorization_session ||= ProviderAuthorizationSession.where(
              installation: current_installation,
              provider_handle: "codex_subscription",
              status: "pending"
            ).order(issued_at: :desc, id: :desc).first
          end

          def authorization_payload(authorization_session: pending_authorization_session, authorization_url: nil)
            credential = current_credential
            {
              "provider_handle" => "codex_subscription",
              "status" => authorization_status(credential:, authorization_session: authorization_session),
              "configured" => credential.present?,
              "enabled" => true,
              "usable" => credential&.usable_for_provider_requests? || false,
              "reauthorization_required" => credential&.reauthorization_required? || false,
              "authorization_url" => authorization_url,
              "expires_at" => credential&.expires_at&.iso8601(6),
              "last_refreshed_at" => credential&.last_refreshed_at&.iso8601(6),
              "refresh_failed_at" => credential&.refresh_failed_at&.iso8601(6),
              "refresh_failure_reason" => credential&.refresh_failure_reason,
            }.compact
          end

          def authorization_status(credential:, authorization_session:)
            return "pending" if authorization_session&.active?
            return "reauthorization_required" if credential&.reauthorization_required?
            return "authorized" if credential&.usable_for_provider_requests?

            "missing"
          end

          def callback_redirect_uri
            "#{request.base_url}/app_api/admin/llm_providers/codex_subscription/authorization/callback"
          end
        end
      end
    end
  end
end
