module AppAPI
  module Admin
    module LLMProviders
      class CredentialsController < BaseController
        def update
          provider = provider_resource
          raise ArgumentError, "provider does not accept credentials" unless provider.fetch("requires_credential")
          raise ArgumentError, "oauth credentials must use the oauth authorization flow" if provider.fetch("credential_kind") == "oauth_codex"

          secret = credential_params["secret"]
          raise ArgumentError, "secret is required" if secret.blank?

          ProviderCredentials::UpsertSecret.call(
            installation: current_installation,
            actor: current_user,
            provider_handle: provider_handle,
            credential_kind: provider.fetch("credential_kind"),
            secret: secret,
            metadata: credential_params.fetch("metadata", {})
          )

          render_method_response(
            method_id: "admin_llm_provider_credential_update",
            llm_provider: AppSurface::Queries::Admin::ShowLLMProvider.call(
              installation: current_installation,
              provider_handle: provider_handle
            )
          )
        rescue ArgumentError => error
          render_method_response(
            method_id: "admin_llm_provider_credential_update_error",
            status: :unprocessable_entity,
            error: error.message
          )
        end

        private

        def credential_params
          params.permit(:secret, metadata: {}).to_h.deep_stringify_keys
        end
      end
    end
  end
end
