module ClosableRuntimeResource
  extend ActiveSupport::Concern

  included do
    enum :close_state,
      {
        open: "open",
        requested: "requested",
        acknowledged: "acknowledged",
        closed: "closed",
        failed: "failed",
      },
      prefix: :close,
      validate: true

    validate :close_outcome_payload_must_be_hash
    validate :close_lifecycle_pairings
  end

  private

  def close_outcome_payload_must_be_hash
    errors.add(:close_outcome_payload, "must be a hash") unless close_outcome_payload.is_a?(Hash)
  end

  def close_lifecycle_pairings
    return if close_state.blank?

    if close_open?
      if close_tracking_fields_present?
        errors.add(:close_state, "must remain open only while close metadata is blank")
      end
      return
    end

    errors.add(:close_reason_kind, "must exist when close has been requested") if close_reason_kind.blank?
    errors.add(:close_requested_at, "must exist when close has been requested") if close_requested_at.blank?

    if close_acknowledged?
      errors.add(:close_acknowledged_at, "must exist when close has been acknowledged") if close_acknowledged_at.blank?
    end

    if close_closed? || close_failed?
      errors.add(:close_outcome_kind, "must exist when close has a terminal outcome") if close_outcome_kind.blank?
    elsif close_outcome_kind.present?
      errors.add(:close_outcome_kind, "must be blank before close reaches a terminal outcome")
    end
  end

  def close_tracking_fields_present?
    close_reason_kind.present? ||
      close_requested_at.present? ||
      close_grace_deadline_at.present? ||
      close_force_deadline_at.present? ||
      close_acknowledged_at.present? ||
      close_outcome_kind.present? ||
      close_outcome_payload.present?
  end
end
