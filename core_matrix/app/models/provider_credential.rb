class ProviderCredential < ApplicationRecord
  encrypts :secret

  belongs_to :installation

  validates :provider_handle, presence: true, uniqueness: { scope: [:installation_id, :credential_kind] }
  validates :credential_kind, presence: true
  validates :secret, presence: true
  validates :last_rotated_at, presence: true
  validate :metadata_must_be_hash

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a Hash") unless metadata.is_a?(Hash)
  end
end
