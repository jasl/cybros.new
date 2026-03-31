class ProviderRequestControl < ApplicationRecord
  belongs_to :installation

  validates :provider_handle, presence: true, uniqueness: { scope: :installation_id }
  validate :metadata_must_be_hash

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a Hash") unless metadata.is_a?(Hash)
  end
end
