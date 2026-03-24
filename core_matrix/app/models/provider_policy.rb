class ProviderPolicy < ApplicationRecord
  belongs_to :installation

  validates :provider_handle, presence: true, uniqueness: { scope: :installation_id }
  validates :max_concurrent_requests, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :throttle_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :throttle_period_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :selection_defaults_must_be_hash
  validate :provider_handle_must_exist_in_catalog
  validate :throttle_pairing

  private

  def selection_defaults_must_be_hash
    errors.add(:selection_defaults, "must be a Hash") unless selection_defaults.is_a?(Hash)
  end

  def provider_handle_must_exist_in_catalog
    return if provider_handle.blank?
    return if ProviderCatalog::Load.call.providers.key?(provider_handle)

    errors.add(:provider_handle, "must exist in the provider catalog")
  end

  def throttle_pairing
    return if throttle_limit.present? && throttle_period_seconds.present?
    return if throttle_limit.blank? && throttle_period_seconds.blank?

    errors.add(:base, "throttle_limit and throttle_period_seconds must be set together")
  end
end
