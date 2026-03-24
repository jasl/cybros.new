module ProviderCatalog
  class Validate
    InvalidCatalog = Class.new(StandardError)

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

        normalized[provider_handle] = {
          display_name: validate_string!(provider_definition["display_name"], "provider #{provider_handle} display_name"),
          metadata: normalize_hash(provider_definition["metadata"], label: "provider #{provider_handle} metadata").deep_symbolize_keys,
          models: validate_models(provider_handle, models),
        }
      end
    end

    def validate_models(provider_handle, models)
      models.each_with_object({}) do |(model_ref, raw_model_definition), normalized|
        validate_format!(model_ref, MODEL_REF_FORMAT, "model ref")

        model_definition = normalize_hash(raw_model_definition, label: "#{provider_handle}/#{model_ref} definition")

        normalized[model_ref] = {
          display_name: validate_string!(model_definition["display_name"], "#{provider_handle}/#{model_ref} display_name"),
          context_window_tokens: validate_integer!(model_definition["context_window_tokens"], "#{provider_handle}/#{model_ref} context_window_tokens"),
          max_output_tokens: validate_integer!(model_definition["max_output_tokens"], "#{provider_handle}/#{model_ref} max_output_tokens"),
          metadata: normalize_hash(model_definition["metadata"], label: "#{provider_handle}/#{model_ref} metadata").deep_symbolize_keys,
          capabilities: validate_capabilities(provider_handle, model_ref, model_definition["capabilities"]),
        }
      end
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
    end
  end
end
