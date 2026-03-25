class CanonicalStoreValue < ApplicationRecord
  MAX_PAYLOAD_BYTESIZE = 2.megabytes

  has_many :canonical_store_entries, dependent: :restrict_with_exception

  before_validation :derive_payload_metadata

  validates :typed_value_payload, presence: true
  validates :payload_sha256, presence: true
  validates :payload_bytesize,
    presence: true,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: MAX_PAYLOAD_BYTESIZE,
    }

  validate :typed_value_payload_must_be_hash

  private

  def derive_payload_metadata
    return unless typed_value_payload.is_a?(Hash)

    serialized_payload = typed_value_payload.to_json
    self.payload_bytesize = serialized_payload.bytesize
    self.payload_sha256 = Digest::SHA256.hexdigest(serialized_payload)
  end

  def typed_value_payload_must_be_hash
    errors.add(:typed_value_payload, "must be a hash") unless typed_value_payload.is_a?(Hash)
  end
end
