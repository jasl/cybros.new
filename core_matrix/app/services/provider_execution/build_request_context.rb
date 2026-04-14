module ProviderExecution
  class BuildRequestContext
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, execution_snapshot:)
      @turn = turn
      @execution_snapshot = execution_snapshot
    end

    def call
      model_context = @execution_snapshot.model_context
      provider_execution = @execution_snapshot.provider_execution
      budget_hints = @execution_snapshot.budget_hints

      raise_invalid!("requires a resolved provider handle") if model_context["provider_handle"].blank?
      raise_invalid!("requires a resolved model ref") if model_context["model_ref"].blank?

      ProviderRequestContext.new(
        "provider_handle" => model_context.fetch("provider_handle"),
        "model_ref" => model_context.fetch("model_ref"),
        "api_model" => model_context.fetch("api_model"),
        "wire_api" => provider_execution.fetch("wire_api"),
        "transport" => model_context.fetch("transport"),
        "tokenizer_hint" => model_context.fetch("tokenizer_hint"),
        "capabilities" => deep_stringify(model_context.fetch("capabilities", {})),
        "execution_settings" => provider_execution.fetch("execution_settings"),
        "hard_limits" => budget_hints.fetch("hard_limits"),
        "advisory_hints" => budget_hints.fetch("advisory_hints"),
        "provider_metadata" => deep_stringify(model_context.fetch("provider_metadata", {})),
        "model_metadata" => deep_stringify(model_context.fetch("model_metadata", {})),
      )
    rescue KeyError, ProviderRequestContext::InvalidContext => error
      raise_invalid!(error.message)
    end

    private

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), out|
          out[key.to_s] = deep_stringify(nested_value)
        end
      when Array
        value.map { |item| deep_stringify(item) }
      else
        value
      end
    end

    def raise_invalid!(message)
      @turn.errors.add(:resolved_config_snapshot, message)
      raise ActiveRecord::RecordInvalid, @turn
    end
  end
end
