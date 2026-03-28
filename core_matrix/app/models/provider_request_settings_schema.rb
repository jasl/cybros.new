class ProviderRequestSettingsSchema
  InvalidSettings = Class.new(StandardError)

  SCHEMAS = {
    "chat_completions" => {
      "temperature" => :non_negative_number,
      "top_p" => :probability,
      "top_k" => :non_negative_integer,
      "min_p" => :probability,
      "presence_penalty" => :number,
      "repetition_penalty" => :positive_number,
    },
    "responses" => {
      "reasoning_effort" => :string,
      "temperature" => :non_negative_number,
      "top_p" => :probability,
      "top_k" => :non_negative_integer,
      "min_p" => :probability,
      "presence_penalty" => :number,
      "repetition_penalty" => :positive_number,
    },
  }.freeze

  def self.for(wire_api)
    schema = SCHEMAS[wire_api.to_s]
    raise InvalidSettings, "unsupported wire api for request settings: #{wire_api}" if schema.blank?

    new(wire_api: wire_api, schema: schema)
  end

  attr_reader :wire_api

  def initialize(wire_api:, schema:)
    @wire_api = wire_api.to_s
    @schema = schema.deep_stringify_keys.freeze
  end

  def allowed_keys
    @allowed_keys ||= @schema.keys.sort
  end

  def validate_request_defaults!(request_defaults, label_prefix:)
    defaults = normalize_hash(request_defaults, "#{label_prefix} request_defaults")
    unknown_keys = defaults.keys - allowed_keys

    if unknown_keys.any?
      raise InvalidSettings, "#{label_prefix} request_defaults contains unsupported keys: #{unknown_keys.join(", ")}"
    end

    defaults.each do |key, value|
      validate_value!(key, value, "#{label_prefix} request_default #{key}")
    end

    defaults
  end

  def merge_execution_settings(request_defaults:, runtime_overrides:)
    defaults = normalize_hash(request_defaults, "request_defaults").slice(*allowed_keys)
    overrides = normalize_hash(runtime_overrides, "runtime_overrides").slice(*allowed_keys)

    overrides.each do |key, value|
      validate_value!(key, value, "runtime_override #{key}")
    end

    defaults.merge(overrides)
  end

  private

  def normalize_hash(value, label)
    raise InvalidSettings, "#{label} must be a hash" unless value.is_a?(Hash)

    value.deep_stringify_keys
  end

  def validate_value!(key, value, label)
    case @schema.fetch(key)
    when :string
      string = value.to_s
      raise InvalidSettings, "#{label} must be present" if string.blank?
    when :number
      raise InvalidSettings, "#{label} must be a number" unless value.is_a?(Numeric)
    when :positive_number
      raise InvalidSettings, "#{label} must be a positive number" unless value.is_a?(Numeric) && value.positive?
    when :non_negative_number
      raise InvalidSettings, "#{label} must be a number greater than or equal to 0" unless value.is_a?(Numeric) && value >= 0
    when :non_negative_integer
      unless value.is_a?(Integer) && value >= 0
        raise InvalidSettings, "#{label} must be an integer greater than or equal to 0"
      end
    when :probability
      raise InvalidSettings, "#{label} must be a number between 0 and 1 inclusive" unless value.is_a?(Numeric) && value >= 0 && value <= 1
    else
      raise InvalidSettings, "#{label} validation is unsupported"
    end
  end
end
