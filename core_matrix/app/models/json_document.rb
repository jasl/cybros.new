class JsonDocument < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  MAX_CONTENT_BYTESIZE = 8.megabytes

  belongs_to :installation

  before_validation :derive_content_metadata

  validates :document_kind, presence: true
  validates :content_sha256, presence: true
  validates :content_bytesize,
    presence: true,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: MAX_CONTENT_BYTESIZE,
    }
  validate :payload_must_be_json_container

  data_lifecycle_kind! :reference_owned

  private

  def derive_content_metadata
    return unless payload.is_a?(Hash) || payload.is_a?(Array)

    serialized_payload = JSON.generate(payload)
    self.content_bytesize = serialized_payload.bytesize
    self.content_sha256 = Digest::SHA256.hexdigest(serialized_payload)
  end

  def payload_must_be_json_container
    return if payload.is_a?(Hash) || payload.is_a?(Array)

    errors.add(:payload, "must be a hash or array")
  end
end
