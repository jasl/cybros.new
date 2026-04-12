module AppAPI
  module Admin
    module LLMProviders
      class ConnectionTestsController < BaseController
        def create
          provider_handle = params.fetch(:provider)
          connection_check = ProviderConnectionChecks::UpsertLatest.call(
            installation: current_installation,
            actor: current_user,
            provider_handle: provider_handle
          )
          ProviderConnectionChecks::ExecuteJob.perform_later(connection_check.public_id)

          render_method_response(
            method_id: "admin_llm_provider_test_connection",
            status: :accepted,
            llm_provider: AppSurface::Queries::Admin::ShowLLMProvider.call(
              installation: current_installation,
              provider_handle: provider_handle
            )
          )
        rescue ArgumentError => error
          render_method_response(
            method_id: "admin_llm_provider_test_connection_error",
            status: :unprocessable_entity,
            error: error.message
          )
        end
      end
    end
  end
end
