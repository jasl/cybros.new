class ProviderRequestLease < ApplicationRecord
  belongs_to :installation
  belongs_to :workflow_run, optional: true
  belongs_to :workflow_node, optional: true

  validates :provider_handle, presence: true
  validates :lease_token, presence: true, uniqueness: true
  validate :metadata_must_be_hash

  scope :active, -> { where(released_at: nil) }
  scope :for_provider, ->(installation:, provider_handle:) do
    where(installation: installation, provider_handle: provider_handle.to_s)
  end

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a Hash") unless metadata.is_a?(Hash)
  end
end
