module AppAPI
  module Admin
    module LLMProviders
      class PoliciesController < BaseController
        def update
          provider = provider_resource

          ProviderPolicies::Upsert.call(
            installation: current_installation,
            actor: current_user,
            provider_handle: provider_handle,
            enabled: provider.fetch("policy").fetch("enabled"),
            selection_defaults: policy_params.fetch("selection_defaults", {})
          )

          render_method_response(
            method_id: "admin_llm_provider_policy_update",
            llm_provider: AppSurface::Queries::Admin::ShowLLMProvider.call(
              installation: current_installation,
              provider_handle: provider_handle
            )
          )
        end

        private

        def policy_params
          params.permit(selection_defaults: {}).to_h.deep_stringify_keys
        end
      end
    end
  end
end
