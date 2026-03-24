class ProviderEntitlement < ApplicationRecord
  enum :window_kind,
    {
      unlimited: "unlimited",
      rolling_five_hours: "rolling_five_hours",
      calendar_day: "calendar_day",
      calendar_month: "calendar_month",
    },
    validate: true

  belongs_to :installation

  validates :provider_handle, presence: true, uniqueness: { scope: [:installation_id, :entitlement_key] }
  validates :entitlement_key, presence: true
  validates :quota_limit, numericality: { only_integer: true, greater_than: 0 }
  validate :metadata_must_be_hash
  validate :provider_handle_must_exist_in_catalog
  validate :window_seconds_requirements

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a Hash") unless metadata.is_a?(Hash)
  end

  def provider_handle_must_exist_in_catalog
    return if provider_handle.blank?
    return if ProviderCatalog::Load.call.providers.key?(provider_handle)

    errors.add(:provider_handle, "must exist in the provider catalog")
  end

  def window_seconds_requirements
    if rolling_five_hours? && window_seconds != 5.hours.to_i
      errors.add(:window_seconds, "must equal five hours for rolling_five_hours")
    end

    if unlimited? && window_seconds.present?
      errors.add(:window_seconds, "must be blank when window_kind is unlimited")
    end
  end
end
