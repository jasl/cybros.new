class ProviderRequestContext
  InvalidContext = Class.new(StandardError)

  def self.wrap(payload_or_context)
    return payload_or_context if payload_or_context.is_a?(self)

    new(payload_or_context)
  end

  REQUIRED_STRING_KEYS = %w[
    provider_handle
    model_ref
    api_model
    wire_api
    transport
    tokenizer_hint
  ].freeze

  REQUIRED_HASH_KEYS = %w[
    capabilities
    execution_settings
    hard_limits
    advisory_hints
    provider_metadata
    model_metadata
  ].freeze

  def initialize(payload)
    @payload = normalize_payload(payload)
    validate!
  end

  REQUIRED_STRING_KEYS.each do |key|
    define_method(key) { @payload.fetch(key) }
  end

  REQUIRED_HASH_KEYS.each do |key|
    define_method(key) { @payload.fetch(key).deep_dup }
  end

  def to_h
    @payload.deep_dup
  end

  private

  def normalize_payload(payload)
    raise InvalidContext, "provider request context must be a hash" unless payload.is_a?(Hash)

    payload.deep_stringify_keys
  end

  def validate!
    REQUIRED_STRING_KEYS.each do |key|
      value = @payload[key]
      raise InvalidContext, "#{key} must be present" if value.to_s.blank?
    end

    REQUIRED_HASH_KEYS.each do |key|
      raise InvalidContext, "#{key} must be a hash" unless @payload[key].is_a?(Hash)
    end
  end
end
