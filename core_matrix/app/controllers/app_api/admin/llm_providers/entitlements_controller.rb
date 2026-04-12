module AppAPI
  module Admin
    module LLMProviders
      class EntitlementsController < AppAPI::Admin::BaseController
        def update
          ProviderEntitlements::Replace.call(
            installation: current_installation,
            actor: current_user,
            provider_handle: params.fetch(:provider),
            entitlements: entitlement_params.fetch("entitlements", [])
          )

          render_method_response(
            method_id: "admin_llm_provider_entitlements_update",
            llm_provider: AppSurface::Queries::Admin::ShowLLMProvider.call(
              installation: current_installation,
              provider_handle: params.fetch(:provider)
            )
          )
        end

        private

        def entitlement_params
          params.permit(entitlements: [:entitlement_key, :window_kind, :quota_limit, :active, { metadata: {} }]).to_h.deep_stringify_keys
        end
      end
    end
  end
end
