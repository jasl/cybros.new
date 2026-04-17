module AppAPI
  module Admin
    module LLMProviders
      module CodexSubscription
        class AuthorizationsController < AppAPI::Admin::BaseController
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
              provider_handle: "codex_subscription"
            )

            render_method_response(
              method_id: "admin_codex_subscription_authorization_create",
              authorization: authorization_payload(
                authorization_session: result.fetch(:authorization_session)
              )
            )
          rescue LLMProviders::CodexSubscription::OAuthClient::RequestFailed => error
            render_method_response(
              method_id: "admin_codex_subscription_authorization_create_error",
              status: :unprocessable_entity,
              error: error.message
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

          def poll
            ProviderAuthorizationSessions::Poll.call(
              installation: current_installation,
              provider_handle: "codex_subscription"
            )
            reset_authorization_state_cache!

            render_method_response(
              method_id: "admin_codex_subscription_authorization_poll",
              authorization: authorization_payload
            )
          rescue ProviderAuthorizationSessions::Poll::NoActiveSession,
                 ProviderAuthorizationSessions::Poll::TerminalPollFailure => error
            render_method_response(
              method_id: "admin_codex_subscription_authorization_poll_error",
              status: :unprocessable_entity,
              error: error.message
            )
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
            ).where("expires_at > ?", Time.current).order(issued_at: :desc, id: :desc).first
          end

          def authorization_payload(authorization_session: pending_authorization_session)
            credential = current_credential
            {
              "provider_handle" => "codex_subscription",
              "status" => authorization_status(credential:, authorization_session: authorization_session),
              "configured" => credential.present?,
              "enabled" => true,
              "usable" => credential&.usable_for_provider_requests? || false,
              "reauthorization_required" => credential&.reauthorization_required? || false,
              "verification_uri" => authorization_session&.active? ? authorization_session.verification_uri : nil,
              "user_code" => authorization_session&.active? ? authorization_session.user_code : nil,
              "poll_interval_seconds" => authorization_session&.active? ? authorization_session.poll_interval_seconds : nil,
              "expires_at" => authorization_session&.active? ? authorization_session.expires_at&.iso8601(6) : credential&.expires_at&.iso8601(6),
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

          def reset_authorization_state_cache!
            @current_credential = nil
            @pending_authorization_session = nil
          end
        end
      end
    end
  end
end
