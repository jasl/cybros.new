module MockLLM
  module V1
    class ModelsController < MockLLM::V1::ApplicationController
      def index
        now = Time.current.to_i
        dev_models = ProviderCatalog::Load.call.provider("dev").fetch(:models)

        render json: {
          object: "list",
          data: dev_models.map do |model_ref, _model_definition|
            {
              id: model_ref,
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
