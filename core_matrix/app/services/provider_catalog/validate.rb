module ProviderCatalog
  class Validate
    InvalidCatalog = Class.new(StandardError)
    SUPPORTED_VERSIONS = [1].freeze

    PROVIDER_HANDLE_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
    MODEL_REF_FORMAT = /\A[a-z0-9][a-z0-9._-]*\z/
    ROLE_NAME_FORMAT = /\A[a-z0-9][a-z0-9_]*\z/
    REQUIRED_MULTIMODAL_INPUTS = %w[image audio video file].freeze
    REQUIRED_CAPABILITY_FLAGS = %w[text_output tool_calls structured_output].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(catalog = nil, **kwargs)
      source = kwargs.any? ? kwargs : catalog
      @catalog = normalize_hash(source, label: "catalog")
    end

    def call
      validate_version!(@catalog["version"])
      providers = validate_providers(@catalog["providers"])
      model_roles = validate_model_roles(@catalog["model_roles"], providers)

      {
        providers: providers,
        model_roles: model_roles,
      }
    end

    private

    def validate_providers(raw_providers)
      providers = normalize_hash(raw_providers, label: "providers")

      providers.each_with_object({}) do |(provider_handle, raw_provider_definition), normalized|
        validate_format!(provider_handle, PROVIDER_HANDLE_FORMAT, "provider handle")

        provider_definition = normalize_hash(raw_provider_definition, label: "provider #{provider_handle}")
        models = normalize_hash(provider_definition["models"], label: "provider #{provider_handle} models")
        wire_api = nil

        normalized[provider_handle] = {
          display_name: validate_string!(provider_definition["display_name"], "provider #{provider_handle} display_name"),
          enabled: validate_boolean!(provider_definition["enabled"], "provider #{provider_handle} enabled"),
          environments: validate_string_array!(provider_definition["environments"], "provider #{provider_handle} environments"),
          adapter_key: validate_string!(provider_definition["adapter_key"], "provider #{provider_handle} adapter_key"),
          base_url: validate_string!(provider_definition["base_url"], "provider #{provider_handle} base_url"),
          headers: normalize_hash(provider_definition["headers"], label: "provider #{provider_handle} headers"),
          wire_api: wire_api = validate_string!(provider_definition["wire_api"], "provider #{provider_handle} wire_api"),
          transport: validate_string!(provider_definition["transport"], "provider #{provider_handle} transport"),
          responses_path: optional_string(provider_definition["responses_path"], "provider #{provider_handle} responses_path"),
          requires_credential: validate_boolean!(provider_definition["requires_credential"], "provider #{provider_handle} requires_credential"),
          credential_kind: validate_string!(provider_definition["credential_kind"], "provider #{provider_handle} credential_kind"),
          metadata: normalize_hash(provider_definition["metadata"], label: "provider #{provider_handle} metadata").deep_symbolize_keys,
          request_governor: validate_request_governor(provider_handle, provider_definition["request_governor"]),
          models: validate_models(provider_handle, wire_api, models),
        }
      end
    end

    def validate_models(provider_handle, wire_api, models)
      models.each_with_object({}) do |(model_ref, raw_model_definition), normalized|
        validate_format!(model_ref, MODEL_REF_FORMAT, "model ref")

        model_definition = normalize_hash(raw_model_definition, label: "#{provider_handle}/#{model_ref} definition")

        normalized[model_ref] = {
          enabled: validate_model_enabled(model_definition["enabled"], "#{provider_handle}/#{model_ref} enabled"),
          display_name: validate_string!(model_definition["display_name"], "#{provider_handle}/#{model_ref} display_name"),
          api_model: validate_string!(model_definition["api_model"], "#{provider_handle}/#{model_ref} api_model"),
          tokenizer_hint: validate_string!(model_definition["tokenizer_hint"], "#{provider_handle}/#{model_ref} tokenizer_hint"),
          context_window_tokens: validate_integer!(model_definition["context_window_tokens"], "#{provider_handle}/#{model_ref} context_window_tokens"),
          max_output_tokens: validate_integer!(model_definition["max_output_tokens"], "#{provider_handle}/#{model_ref} max_output_tokens"),
          context_soft_limit_ratio: validate_ratio!(model_definition["context_soft_limit_ratio"], "#{provider_handle}/#{model_ref} context_soft_limit_ratio"),
          request_defaults: validate_request_defaults(provider_handle, model_ref, wire_api, model_definition["request_defaults"]),
          metadata: normalize_hash(model_definition["metadata"], label: "#{provider_handle}/#{model_ref} metadata").deep_symbolize_keys,
          capabilities: validate_capabilities(provider_handle, model_ref, model_definition["capabilities"]),
        }
      end
    end

    def validate_model_enabled(value, label)
      return true if value.nil?

      validate_boolean!(value, label)
    end

    def validate_request_defaults(provider_handle, model_ref, wire_api, raw_request_defaults)
      request_defaults = normalize_hash(raw_request_defaults, label: "#{provider_handle}/#{model_ref} request_defaults")
      ProviderRequestSettingsSchema
        .for(wire_api)
        .validate_request_defaults!(
          request_defaults,
          label_prefix: "#{provider_handle}/#{model_ref}"
        )
    rescue ProviderRequestSettingsSchema::InvalidSettings => error
      raise InvalidCatalog, error.message
    end

    def validate_capabilities(provider_handle, model_ref, raw_capabilities)
      capabilities = normalize_hash(raw_capabilities, label: "#{provider_handle}/#{model_ref} capabilities")

      REQUIRED_CAPABILITY_FLAGS.each do |flag|
        validate_boolean!(capabilities[flag], "#{provider_handle}/#{model_ref} capability #{flag}")
      end

      multimodal_inputs = normalize_hash(
        capabilities["multimodal_inputs"],
        label: "#{provider_handle}/#{model_ref} multimodal_inputs"
      )

      REQUIRED_MULTIMODAL_INPUTS.each do |input_name|
        validate_boolean!(multimodal_inputs[input_name], "#{provider_handle}/#{model_ref} multimodal input #{input_name}")
      end

      {
        text_output: capabilities["text_output"],
        tool_calls: capabilities["tool_calls"],
        structured_output: capabilities["structured_output"],
        multimodal_inputs: {
          image: multimodal_inputs["image"],
          audio: multimodal_inputs["audio"],
          video: multimodal_inputs["video"],
          file: multimodal_inputs["file"],
        },
      }
    end

    def validate_request_governor(provider_handle, raw_request_governor)
      return {} if raw_request_governor.nil?

      request_governor = normalize_hash(raw_request_governor, label: "provider #{provider_handle} request_governor")

      {
        max_concurrent_requests: validate_positive_number!(
          request_governor["max_concurrent_requests"],
          "provider #{provider_handle} request_governor max_concurrent_requests"
        ).to_i,
        throttle_limit: validate_positive_number!(
          request_governor["throttle_limit"],
          "provider #{provider_handle} request_governor throttle_limit"
        ).to_i,
        throttle_period_seconds: validate_positive_number!(
          request_governor["throttle_period_seconds"],
          "provider #{provider_handle} request_governor throttle_period_seconds"
        ).to_i,
      }
    end

    def validate_model_roles(raw_model_roles, providers)
      model_roles = normalize_hash(raw_model_roles, label: "model_roles")

      model_roles.each_with_object({}) do |(role_name, raw_candidates), normalized|
        validate_format!(role_name, ROLE_NAME_FORMAT, "role name")

        candidates = Array(raw_candidates)
        raise InvalidCatalog, "role #{role_name} candidates must not be empty" if candidates.empty?

        normalized[role_name] = candidates.map do |candidate|
          candidate_ref = validate_string!(candidate, "model role candidate")
          provider_handle, model_ref = candidate_ref.split("/", 2)

          unless provider_handle.present? && model_ref.present?
            raise InvalidCatalog, "model role candidate must use provider_handle/model_ref form: #{candidate_ref}"
          end

          unless providers.fetch(provider_handle, {}).fetch(:models, {}).key?(model_ref)
            raise InvalidCatalog, "unknown model role candidate: #{candidate_ref}"
          end

          candidate_ref
        end
      end
    end

    def normalize_hash(value, label:)
      candidate = value
      raise InvalidCatalog, "#{label} must be a hash" unless candidate.is_a?(Hash)

      stringify_hash_keys(candidate)
    end

    def validate_version!(value)
      raise InvalidCatalog, "catalog version must be a supported integer" unless value.is_a?(Integer) && SUPPORTED_VERSIONS.include?(value)

      value
    end

    def stringify_hash_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), normalized|
          normalized[key.to_s] = stringify_hash_keys(nested_value)
        end
      when Array
        value.map { |item| stringify_hash_keys(item) }
      else
        value
      end
    end

    def validate_format!(value, format, label)
      string = validate_string!(value, label)
      raise InvalidCatalog, "#{label} is invalid: #{string}" unless format.match?(string)
    end

    def validate_string!(value, label)
      string = value.to_s
      raise InvalidCatalog, "#{label} must be present" if string.blank?

      string
    end

    def validate_integer!(value, label)
      raise InvalidCatalog, "#{label} must be a positive integer" unless value.is_a?(Integer) && value.positive?

      value
    end

    def validate_boolean!(value, label)
      raise InvalidCatalog, "#{label} must be boolean" unless value == true || value == false

      value
    end

    def validate_string_array!(value, label)
      raise InvalidCatalog, "#{label} must be a non-empty array" unless value.is_a?(Array) && value.any?

      value.map { |entry| validate_string!(entry, label) }
    end

    def validate_ratio!(value, label)
      raise InvalidCatalog, "#{label} must be a number between 0 and 1" unless value.is_a?(Numeric) && value.positive? && value <= 1

      value
    end

    def validate_number!(value, label)
      raise InvalidCatalog, "#{label} must be a number" unless value.is_a?(Numeric)

      value
    end

    def validate_positive_number!(value, label)
      raise InvalidCatalog, "#{label} must be a positive number" unless value.is_a?(Numeric) && value.positive?

      value
    end

    def validate_non_negative_number!(value, label)
      raise InvalidCatalog, "#{label} must be a number greater than or equal to 0" unless value.is_a?(Numeric) && value >= 0

      value
    end

    def validate_non_negative_integer!(value, label)
      raise InvalidCatalog, "#{label} must be an integer greater than or equal to 0" unless value.is_a?(Integer) && value >= 0

      value
    end

    def validate_probability!(value, label)
      raise InvalidCatalog, "#{label} must be a number between 0 and 1 inclusive" unless value.is_a?(Numeric) && value >= 0 && value <= 1

      value
    end

    def optional_string(value, label)
      return nil if value.nil?

      validate_string!(value, label)
    end
  end
end
