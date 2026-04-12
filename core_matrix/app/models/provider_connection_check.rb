class ProviderConnectionCheck < ApplicationRecord
  include HasPublicId

  enum :lifecycle_state,
    {
      queued: "queued",
      running: "running",
      succeeded: "succeeded",
      failed: "failed",
    },
    validate: true

  belongs_to :installation
  belongs_to :requested_by_user, class_name: "User", optional: true

  validates :provider_handle, presence: true, uniqueness: { scope: :installation_id }
  validate :requested_by_user_installation_match
  validate :request_payload_must_be_hash
  validate :result_payload_must_be_hash
  validate :failure_payload_must_be_hash

  private

  def requested_by_user_installation_match
    return if requested_by_user.blank?
    return if requested_by_user.installation_id == installation_id

    errors.add(:requested_by_user, "must belong to the same installation")
  end

  def request_payload_must_be_hash
    errors.add(:request_payload, "must be a hash") unless request_payload.is_a?(Hash)
  end

  def result_payload_must_be_hash
    errors.add(:result_payload, "must be a hash") unless result_payload.is_a?(Hash)
  end

  def failure_payload_must_be_hash
    errors.add(:failure_payload, "must be a hash") unless failure_payload.is_a?(Hash)
  end
end
