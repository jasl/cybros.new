class ProviderLoopPolicy
  InvalidPolicy = Class.new(StandardError)

  DEFAULT_MAX_ROUNDS = 64
  MAX_ROUNDS_LIMIT = 256
  DEFAULT_MAX_PARALLEL_TOOL_CALLS = 1
  KNOWN_KEYS = %w[max_rounds parallel_tool_calls max_parallel_tool_calls loop_detection].freeze

  DEFAULT_POLICY = {
    "max_rounds" => DEFAULT_MAX_ROUNDS,
    "parallel_tool_calls" => false,
    "max_parallel_tool_calls" => DEFAULT_MAX_PARALLEL_TOOL_CALLS,
    "loop_detection" => {
      "enabled" => false,
    },
  }.freeze

  def self.build(...)
    new(...).build
  end

  def initialize(runtime_overrides:)
    @runtime_overrides = normalize_hash(runtime_overrides)
  end

  def build
    policy = DEFAULT_POLICY.deep_dup
    overrides = extracted_policy_overrides

    if overrides.key?("max_rounds")
      policy["max_rounds"] = validate_max_rounds!(overrides.fetch("max_rounds"))
    end

    if overrides.key?("parallel_tool_calls")
      policy["parallel_tool_calls"] = validate_boolean!(
        overrides.fetch("parallel_tool_calls"),
        "runtime_override loop_policy.parallel_tool_calls"
      )
    end

    if overrides.key?("max_parallel_tool_calls")
      policy["max_parallel_tool_calls"] = validate_max_parallel_tool_calls!(
        overrides.fetch("max_parallel_tool_calls")
      )
    end

    if overrides.key?("loop_detection")
      policy["loop_detection"] = build_loop_detection!(
        overrides.fetch("loop_detection"),
        current: policy.fetch("loop_detection")
      )
    end

    policy
  end

  private

  def extracted_policy_overrides
    candidate = merged_runtime_overrides
    explicit_policy = candidate["loop_policy"]
    top_level = candidate.slice(*KNOWN_KEYS)

    unless explicit_policy.present?
      raise InvalidPolicy, "runtime_override loop policy overrides must be nested under loop_policy" if top_level.present?

      return {}
    end

    raise InvalidPolicy, "runtime_override loop_policy must be a hash" unless explicit_policy.is_a?(Hash)
    raise InvalidPolicy, "runtime_override loop policy overrides must be nested under loop_policy" if top_level.present?

    explicit_policy.deep_stringify_keys.slice(*KNOWN_KEYS)
  end

  def merged_runtime_overrides
    wrapped_config = @runtime_overrides["config"]
    return @runtime_overrides unless wrapped_config.is_a?(Hash)

    @runtime_overrides.merge(wrapped_config.deep_stringify_keys)
  end

  def build_loop_detection!(value, current:)
    normalized = normalize_hash(value, "runtime_override loop_policy.loop_detection")
    result = current.deep_dup

    if normalized.key?("enabled")
      result["enabled"] = validate_boolean!(
        normalized.fetch("enabled"),
        "runtime_override loop_policy.loop_detection.enabled"
      )
    end

    result
  end

  def validate_max_rounds!(value)
    unless value.is_a?(Integer) && value.between?(1, MAX_ROUNDS_LIMIT)
      raise InvalidPolicy, "runtime_override loop_policy.max_rounds must be an integer between 1 and #{MAX_ROUNDS_LIMIT}"
    end

    value
  end

  def validate_max_parallel_tool_calls!(value)
    unless value.is_a?(Integer) && value >= 1
      raise InvalidPolicy, "runtime_override loop_policy.max_parallel_tool_calls must be an integer greater than or equal to 1"
    end

    value
  end

  def validate_boolean!(value, label)
    return value if value == true || value == false

    raise InvalidPolicy, "#{label} must be true or false"
  end

  def normalize_hash(value, label = "runtime_overrides")
    return {} if value.nil?
    raise InvalidPolicy, "#{label} must be a hash" unless value.is_a?(Hash)

    value.deep_stringify_keys
  end
end
