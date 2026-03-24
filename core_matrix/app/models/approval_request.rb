class ApprovalRequest < HumanInteractionRequest
  APPROVAL_RESOLUTION_KINDS = %w[approved denied].freeze

  validate :approval_scope_present
  validate :approval_resolution_kind

  private

  def approval_scope_present
    return if request_payload["approval_scope"].present?

    errors.add(:request_payload, "must include approval_scope")
  end

  def approval_resolution_kind
    return unless resolved?
    return if resolution_kind.in?(APPROVAL_RESOLUTION_KINDS)

    errors.add(:resolution_kind, "must be approved or denied for approval requests")
  end
end
