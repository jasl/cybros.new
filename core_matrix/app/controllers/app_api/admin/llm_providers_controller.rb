module AppAPI
  module Admin
    class LLMProvidersController < BaseController
      def index
        render_method_response(
          method_id: "admin_llm_provider_index",
          llm_providers: AppSurface::Queries::Admin::ListLLMProviders.call(
            installation: current_installation
          )
        )
      end

      def show
        render_method_response(
          method_id: "admin_llm_provider_show",
          llm_provider: AppSurface::Queries::Admin::ShowLLMProvider.call(
            installation: current_installation,
            provider_handle: params.fetch(:provider)
          )
        )
      end

      def update
        provider_handle = params.fetch(:provider)
        provider = AppSurface::Queries::Admin::ShowLLMProvider.call(
          installation: current_installation,
          provider_handle: provider_handle
        )

        ProviderPolicies::Upsert.call(
          installation: current_installation,
          actor: current_user,
          provider_handle: provider_handle,
          enabled: params.fetch(:enabled),
          selection_defaults: provider.fetch("policy").fetch("selection_defaults")
        )

        render_method_response(
          method_id: "admin_llm_provider_update",
          llm_provider: AppSurface::Queries::Admin::ShowLLMProvider.call(
            installation: current_installation,
            provider_handle: provider_handle
          )
        )
      rescue KeyError
        render_method_response(
          method_id: "admin_llm_provider_update_error",
          status: :unprocessable_entity,
          error: "enabled is required"
        )
      end
    end
  end
end
