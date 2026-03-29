module MockLLM
  module V1
    class ModelsController < MockLLM::V1::ApplicationController
      def index
        now = Time.current.to_i
        dev_models = ProviderCatalog::EffectiveCatalog.new
          .candidate_options(provider_handle: "dev")

        render json: {
          object: "list",
          data: dev_models.map do |entry|
            {
              id: entry.fetch("model_ref"),
              object: "model",
              created: now,
              owned_by: "mock_llm",
            }
          end,
        }
      end
    end
  end
end
