class ProviderCredential < ApplicationRecord
  encrypts :secret

  belongs_to :installation

  validates :provider_handle, presence: true, uniqueness: { scope: [:installation_id, :credential_kind] }
  validates :credential_kind, presence: true
  validates :secret, presence: true
  validates :last_rotated_at, presence: true
  validate :metadata_must_be_hash
  validate :provider_handle_must_exist_in_catalog

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a Hash") unless metadata.is_a?(Hash)
  end

  def provider_handle_must_exist_in_catalog
    return if provider_handle.blank?
    return if ProviderCatalog::Load.call.providers.key?(provider_handle)

    errors.add(:provider_handle, "must exist in the provider catalog")
  end
end
