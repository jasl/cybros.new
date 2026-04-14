module AgentAPI
  module Responses
    class InputTokensController < BaseController
      def create
        effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: current_agent_definition_version.installation)
        provider_handle = request_payload.fetch("provider_handle")
        model_ref = request_payload.fetch("model_ref")
        provider_definition = effective_catalog.provider(provider_handle)
        model_definition = effective_catalog.model(provider_handle, model_ref)
        api_model = request_payload["api_model"].presence || model_definition.fetch(:api_model)

        if request_payload["api_model"].present? && request_payload["api_model"] != model_definition.fetch(:api_model)
          render json: { error: "api_model must match the configured catalog model" }, status: :unprocessable_entity
          return
        end

        advisory = ProviderExecution::PromptBudgetAdvisory.call(
          provider_handle: provider_handle,
          model_ref: model_ref,
          api_model: api_model,
          tokenizer_hint: model_definition.fetch(:tokenizer_hint),
          context_window_tokens: model_definition.fetch(:context_window_tokens),
          max_output_tokens: model_definition.fetch(:max_output_tokens),
          context_soft_limit_ratio: model_definition.fetch(:context_soft_limit_ratio),
          input: request_payload.fetch("input")
        )

        render json: advisory
      rescue KeyError => error
        render json: { error: error.message }, status: :unprocessable_entity
      end
    end
  end
end
