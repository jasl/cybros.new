class AuditLog < ApplicationRecord
  include HasPublicId

  belongs_to :installation
  belongs_to :actor, polymorphic: true, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :action, presence: true
  validate :actor_pairing
  validate :subject_pairing
  validate :metadata_must_be_hash

  def self.record!(installation:, action:, actor: nil, subject: nil, metadata: {})
    create!(
      installation: installation,
      actor: actor,
      action: action,
      subject: subject,
      metadata: metadata
    )
  end

  private

  def actor_pairing
    return if actor_id.blank? && actor_type.blank?
    return if actor_id.present? && actor_type.present?

    errors.add(:actor, "must include both type and id")
  end

  def subject_pairing
    return if subject_id.blank? && subject_type.blank?
    return if subject_id.present? && subject_type.present?

    errors.add(:subject, "must include both type and id")
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a Hash") unless metadata.is_a?(Hash)
  end
end
