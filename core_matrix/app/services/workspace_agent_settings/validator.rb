module WorkspaceAgentSettings
  class Validator
    Result = Struct.new(:normalized_payload, :errors, keyword_init: true) do
      def valid?
        errors.empty?
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(settings_payload:, schema:, default_settings:, profile_policy:, default_canonical_config:)
      @settings_payload = settings_payload
      @schema = Schema.normalize_hash(schema)
      @default_settings = Schema.normalize_hash(default_settings)
      @profile_policy = Schema.normalize_hash(profile_policy)
      @default_canonical_config = Schema.normalize_hash(default_canonical_config)
    end

    def call
      return Result.new(normalized_payload: {}, errors: []) if @settings_payload.blank?
      return Result.new(normalized_payload: @settings_payload, errors: ["must be a hash"]) unless @settings_payload.is_a?(Hash)

      raw = translate_legacy_shape(@settings_payload.deep_stringify_keys)
      normalized = normalize_value(raw, @schema)
      normalize_domain_defaults!(normalized)
      errors = []

      errors << "must only contain supported keys" if unsupported_keys?(raw, @schema)
      validate_value(normalized, @schema, nil, errors)
      apply_domain_validation(normalized, errors)

      Result.new(
        normalized_payload: normalized.is_a?(Hash) ? normalized : {},
        errors: errors.uniq
      )
    end

    private

    def normalize_value(value, schema)
      normalized_schema = Schema.normalize_hash(schema)

      case normalized_schema["type"]
      when "object"
        normalize_object(value, normalized_schema)
      when "array"
        normalize_array(value, normalized_schema)
      when "string"
        value.to_s.strip.presence if value.present?
      when "integer"
        return nil if value.respond_to?(:strip) && value.strip.empty?

        converted = Integer(value, exception: false)
        converted.nil? ? value : converted
      when "boolean"
        [true, false].include?(value) ? value : value
      else
        value
      end
    end

    def normalize_object(value, schema)
      return {} unless value.is_a?(Hash)

      properties = Schema.normalize_hash(schema["properties"])
      additional = schema["additionalProperties"]

      value.each_with_object({}) do |(key, raw_nested), out|
        string_key = key.to_s
        child_schema =
          if properties.key?(string_key)
            properties.fetch(string_key)
          elsif additional.is_a?(Hash)
            additional
          end
        next if child_schema.blank?

        normalized_nested = normalize_value(raw_nested, child_schema)
        next if blank_container?(normalized_nested)

        out[string_key] = normalized_nested
      end
    end

    def normalize_array(value, schema)
      Array(value).filter_map do |item|
        normalized_item = normalize_value(item, schema["items"] || {})
        next if blank_container?(normalized_item)

        normalized_item
      end.uniq
    end

    def blank_container?(value)
      value.nil? || value.is_a?(Hash) && value.empty?
    end

    def unsupported_keys?(raw, schema)
      return false unless raw.is_a?(Hash)

      normalized_schema = Schema.normalize_hash(schema)
      properties = Schema.normalize_hash(normalized_schema["properties"])
      additional = normalized_schema["additionalProperties"]

      raw.any? do |key, nested|
        string_key = key.to_s

        if properties.key?(string_key)
          unsupported_keys?(nested, properties.fetch(string_key))
        elsif additional.is_a?(Hash)
          unsupported_keys?(nested, additional)
        else
          additional == false
        end
      end
    end

    def translate_legacy_shape(raw)
      return raw unless raw.is_a?(Hash)

      translated = raw.deep_dup
      interactive = translated["interactive"].is_a?(Hash) ? translated["interactive"].deep_dup : {}
      subagents = translated["subagents"].is_a?(Hash) ? translated["subagents"].deep_dup : {}

      interactive["profile_key"] = translated.delete("interactive_profile_key") if translated.key?("interactive_profile_key")
      interactive["model_selector"] = translated.delete("interactive_model_selector") if translated.key?("interactive_model_selector")

      subagents["default_profile_key"] = translated.delete("default_subagent_profile_key") if translated.key?("default_subagent_profile_key")
      subagents["enabled_profile_keys"] = translated.delete("enabled_subagent_profile_keys") if translated.key?("enabled_subagent_profile_keys")
      subagents["delegation_mode"] = translated.delete("delegation_mode") if translated.key?("delegation_mode")
      subagents["max_concurrent"] = translated.delete("max_concurrent_subagents") if translated.key?("max_concurrent_subagents")
      subagents["max_depth"] = translated.delete("max_subagent_depth") if translated.key?("max_subagent_depth")
      subagents["allow_nested"] = translated.delete("allow_nested_subagents") if translated.key?("allow_nested_subagents")

      if translated.key?("default_subagent_model_selector_hint")
        subagents["default_model_selector"] = translated.delete("default_subagent_model_selector_hint")
      elsif translated.key?("default_subagent_model_selector")
        subagents["default_model_selector"] = translated.delete("default_subagent_model_selector")
      end

      if translated["subagent_model_selectors"].is_a?(Hash)
        profile_overrides = subagents["profile_overrides"].is_a?(Hash) ? subagents["profile_overrides"].deep_dup : {}
        translated.delete("subagent_model_selectors").each do |profile_key, selector|
          profile_overrides[profile_key.to_s] = { "model_selector" => selector }
        end
        subagents["profile_overrides"] = profile_overrides
      end

      translated["interactive"] = interactive if interactive.any?
      translated["subagents"] = subagents if subagents.any?
      translated
    end

    def validate_value(value, schema, path, errors)
      normalized_schema = Schema.normalize_hash(schema)
      type = normalized_schema["type"]

      case type
      when "object"
        return errors << "#{path} must be an object" if path.present? && !value.is_a?(Hash)
        return unless value.is_a?(Hash)

        properties = Schema.normalize_hash(normalized_schema["properties"])
        additional = normalized_schema["additionalProperties"]
        value.each do |key, nested|
          child_schema =
            if properties.key?(key)
              properties.fetch(key)
            elsif additional.is_a?(Hash)
              additional
            end
          next if child_schema.blank?

          validate_value(nested, child_schema, join_path(path, key), errors)
        end
      when "array"
        return errors << "#{path} must be an array" unless value.is_a?(Array)

        if normalized_schema["uniqueItems"] == true && value.uniq.length != value.length
          errors << "#{path} must contain unique values"
        end
        value.each { |item| validate_value(item, normalized_schema["items"] || {}, path, errors) }
      when "string"
        return errors << "#{path} must be a string" unless value.is_a?(String)
        return if normalized_schema["minLength"].blank? || value.length >= normalized_schema["minLength"].to_i

        errors << "#{path} must be a string"
      when "integer"
        unless value.is_a?(Integer)
          errors << "#{path} must be a positive integer" if path == "subagents.max_concurrent" || path == "subagents.max_depth"
          errors << "#{path} must be an integer" unless path == "subagents.max_concurrent" || path == "subagents.max_depth"
          return
        end
        return if normalized_schema["minimum"].blank? || value >= normalized_schema["minimum"].to_i

        errors << "#{path} must be a positive integer"
      when "boolean"
        errors << "#{path} must be a boolean" unless [true, false].include?(value)
      end

      if normalized_schema["enum"].is_a?(Array) && !normalized_schema["enum"].include?(value)
        errors << "#{path} must be one of: #{normalized_schema["enum"].join(", ")}"
      end
    end

    def join_path(path, key)
      path.present? ? "#{path}.#{key}" : key.to_s
    end

    def apply_domain_validation(normalized, errors)
      return unless normalized.is_a?(Hash)

      interactive_profile_key = current_interactive_profile_key(normalized)
      available_profile_keys = @profile_policy.keys
      specialist_profile_keys = available_profile_keys - [interactive_profile_key]

      validate_known_profile_key(normalized.dig("interactive", "profile_key"), "interactive.profile_key", available_profile_keys, errors)
      validate_known_profile_key(normalized.dig("subagents", "default_profile_key"), "default_subagent_profile_key", available_profile_keys, errors)

      enabled_keys = Array(normalized.dig("subagents", "enabled_profile_keys"))
      unknown_enabled_keys = enabled_keys - specialist_profile_keys
      errors << "enabled_subagent_profile_keys must reference known profile keys" if unknown_enabled_keys.any?

      default_profile_key = normalized.dig("subagents", "default_profile_key")
      if default_profile_key.present? && normalized.dig("subagents").is_a?(Hash) && normalized["subagents"].key?("enabled_profile_keys") && !enabled_keys.include?(default_profile_key)
        errors << "default_subagent_profile_key must be included in enabled_subagent_profile_keys"
      end

      profile_overrides = normalized.dig("subagents", "profile_overrides")
      if profile_overrides.is_a?(Hash)
        unknown_override_keys = profile_overrides.keys - specialist_profile_keys
        errors << "subagents.profile_overrides must reference known specialist profile keys" if unknown_override_keys.any?
      end
    end

    def normalize_domain_defaults!(normalized)
      return unless normalized.is_a?(Hash)

      enabled_keys = normalized.dig("subagents", "enabled_profile_keys")
      return unless enabled_keys.is_a?(Array)

      interactive_profile_key = current_interactive_profile_key(normalized)
      normalized["subagents"]["enabled_profile_keys"] = enabled_keys - [interactive_profile_key]
    end

    def validate_known_profile_key(value, label, available_profile_keys, errors)
      return if value.blank? || available_profile_keys.empty?
      return if available_profile_keys.include?(value)

      errors << "#{label} must reference a known profile key"
    end

    def current_interactive_profile_key(normalized)
      normalized.dig("interactive", "profile_key").presence ||
        @default_settings.dig("interactive", "profile_key").presence ||
        @default_canonical_config.dig("interactive", "profile").presence ||
        @default_canonical_config.dig("interactive", "default_profile_key").presence ||
        "main"
    end
  end
end
