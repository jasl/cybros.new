module AppAPI
  module Admin
    module LLMProviders
      class BaseController < AppAPI::Admin::BaseController
        private

        def provider_handle
          params[:provider] || params[:llm_provider_provider] || params.fetch(:provider)
        end

        def provider_resource
          @provider_resource ||= AppSurface::Queries::Admin::ShowLLMProvider.call(
            installation: current_installation,
            provider_handle: provider_handle
          )
        end
      end
    end
  end
end
