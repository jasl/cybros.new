module AppAPI
  module Admin
    module LLMProviders
      class CredentialsController < AppAPI::Admin::BaseController
        def update
          provider = provider_resource
          raise ArgumentError, "provider does not accept credentials" unless provider.fetch("requires_credential")
          raise ArgumentError, "oauth credentials must use the oauth authorization flow" if provider.fetch("credential_kind") == "oauth_codex"

          ProviderCredentials::UpsertSecret.call(
            installation: current_installation,
            actor: current_user,
            provider_handle: params.fetch(:provider),
            credential_kind: provider.fetch("credential_kind"),
            secret: credential_params.fetch("secret"),
            metadata: credential_params.fetch("metadata", {})
          )

          render_method_response(
            method_id: "admin_llm_provider_credential_update",
            llm_provider: AppSurface::Queries::Admin::ShowLLMProvider.call(
              installation: current_installation,
              provider_handle: params.fetch(:provider)
            )
          )
        rescue KeyError
          render_method_response(
            method_id: "admin_llm_provider_credential_update_error",
            status: :unprocessable_entity,
            error: "secret is required"
          )
        rescue ArgumentError => error
          render_method_response(
            method_id: "admin_llm_provider_credential_update_error",
            status: :unprocessable_entity,
            error: error.message
          )
        end

        private

        def provider_resource
          @provider_resource ||= AppSurface::Queries::Admin::ShowLLMProvider.call(
            installation: current_installation,
            provider_handle: params.fetch(:provider)
          )
        end

        def credential_params
          params.permit(:secret, metadata: {}).to_h.deep_stringify_keys
        end
      end
    end
  end
end
