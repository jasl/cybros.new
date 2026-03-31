class ProviderPolicy < ApplicationRecord
  belongs_to :installation

  validates :provider_handle, presence: true, uniqueness: { scope: :installation_id }
  validate :selection_defaults_must_be_hash

  private

  def selection_defaults_must_be_hash
    errors.add(:selection_defaults, "must be a Hash") unless selection_defaults.is_a?(Hash)
  end
end
