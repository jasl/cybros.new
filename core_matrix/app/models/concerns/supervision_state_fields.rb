module SupervisionStateFields
  extend ActiveSupport::Concern

  SUPERVISION_STATES = %w[
    queued
    running
    waiting
    blocked
    completed
    failed
    interrupted
    canceled
  ].freeze
  FOCUS_KINDS = %w[
    planning
    research
    implementation
    testing
    review
    waiting
    general
  ].freeze
  HUMAN_SUMMARY_FIELD_NAMES = %w[
    request_summary
    current_focus_summary
    recent_progress_summary
    waiting_summary
    blocked_summary
    next_step_hint
  ].freeze
  HUMAN_SUMMARY_MAX_LENGTH = 255

  included do
    validates :supervision_state, inclusion: { in: SUPERVISION_STATES }
    validates :focus_kind, inclusion: { in: FOCUS_KINDS }
    validate :human_summary_fields_are_short_strings
    validate :last_progress_at_required_when_supervision_started
    validate :supervision_payload_must_be_hash
  end

  def advance_supervision_sequence!(occurred_at: Time.current)
    attributes = { last_progress_at: occurred_at }
    attributes[:supervision_sequence] = supervision_sequence.to_i + 1 if has_attribute?(:supervision_sequence)
    update!(attributes)
  end

  private

  def human_summary_fields_are_short_strings
    HUMAN_SUMMARY_FIELD_NAMES.each do |attribute_name|
      value = self[attribute_name]
      next if value.nil?

      errors.add(attribute_name, "must be a string") unless value.is_a?(String)
      next unless value.is_a?(String)

      if value.length > HUMAN_SUMMARY_MAX_LENGTH
        errors.add(attribute_name, "is too long (maximum is #{HUMAN_SUMMARY_MAX_LENGTH} characters)")
      end
    end
  end

  def last_progress_at_required_when_supervision_started
    return if supervision_state == "queued"
    return if last_progress_at.present?

    errors.add(:last_progress_at, "must exist when supervision has started")
  end

  def supervision_payload_must_be_hash
    errors.add(:supervision_payload, "must be a hash") unless supervision_payload.is_a?(Hash)
  end
end
