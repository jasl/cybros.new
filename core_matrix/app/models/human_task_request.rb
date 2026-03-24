class HumanTaskRequest < HumanInteractionRequest
  validate :instructions_present
  validate :completed_resolution_kind

  private

  def instructions_present
    return if request_payload["instructions"].present?

    errors.add(:request_payload, "must include instructions")
  end

  def completed_resolution_kind
    return unless resolved?
    return if resolution_kind == "completed"

    errors.add(:resolution_kind, "must be completed for human task requests")
  end
end
