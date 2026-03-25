module ProviderExecution
  class BuildRequestContext
    EXECUTION_SETTING_KEYS = {
      "chat_completions" => %w[
        temperature
        top_p
        top_k
        min_p
        presence_penalty
        repetition_penalty
      ],
      "responses" => %w[
        reasoning_effort
        temperature
        top_p
        top_k
        min_p
        presence_penalty
        repetition_penalty
      ],
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(turn:, catalog: ProviderCatalog::Load.call)
      @turn = turn
      @catalog = catalog
    end

    def call
      raise_invalid!("requires a resolved provider handle") if @turn.resolved_provider_handle.blank?
      raise_invalid!("requires a resolved model ref") if @turn.resolved_model_ref.blank?

      provider = @catalog.provider(@turn.resolved_provider_handle)
      model = @catalog.model(@turn.resolved_provider_handle, @turn.resolved_model_ref)
      wire_api = provider.fetch(:wire_api)
      context_window_tokens = model.fetch(:context_window_tokens)
      context_soft_limit_ratio = model.fetch(:context_soft_limit_ratio)

      {
        "provider_handle" => @turn.resolved_provider_handle,
        "model_ref" => @turn.resolved_model_ref,
        "api_model" => model.fetch(:api_model),
        "wire_api" => wire_api,
        "transport" => provider.fetch(:transport),
        "tokenizer_hint" => model.fetch(:tokenizer_hint),
        "execution_settings" => execution_settings_for(model: model, wire_api: wire_api),
        "hard_limits" => {
          "context_window_tokens" => context_window_tokens,
          "max_output_tokens" => model.fetch(:max_output_tokens),
        },
        "advisory_hints" => {
          "recommended_compaction_threshold" => (context_window_tokens * context_soft_limit_ratio).floor,
        },
        "provider_metadata" => deep_stringify(provider.fetch(:metadata, {})),
        "model_metadata" => deep_stringify(model.fetch(:metadata, {})),
      }
    rescue KeyError => error
      raise_invalid!(error.message)
    end

    private

    def execution_settings_for(model:, wire_api:)
      allowed_keys = EXECUTION_SETTING_KEYS.fetch(wire_api, [])
      settings = model.fetch(:request_defaults, {}).slice(*allowed_keys)

      @turn.effective_config_snapshot.each do |key, value|
        next unless allowed_keys.include?(key)

        settings[key] = value
      end

      settings
    end

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
