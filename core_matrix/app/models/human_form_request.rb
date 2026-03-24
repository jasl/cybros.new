class HumanFormRequest < HumanInteractionRequest
  validate :input_schema_hash
  validate :defaults_hash

  private

  def input_schema_hash
    return if request_payload["input_schema"].is_a?(Hash)

    errors.add(:request_payload, "must include an input_schema hash")
  end

  def defaults_hash
    defaults = request_payload["defaults"]
    return if defaults.nil? || defaults.is_a?(Hash)

    errors.add(:request_payload, "must include a defaults hash when defaults are present")
  end
end
