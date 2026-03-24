module ProviderEntitlements
  class Upsert
    WINDOW_SECONDS_BY_KIND = {
      "unlimited" => nil,
      "rolling_five_hours" => 5.hours.to_i,
      "calendar_day" => 1.day.to_i,
      "calendar_month" => nil,
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, actor:, provider_handle:, entitlement_key:, window_kind:, quota_limit:, active:, metadata: {})
      @installation = installation
      @actor = actor
      @provider_handle = provider_handle
      @entitlement_key = entitlement_key
      @window_kind = window_kind
      @quota_limit = quota_limit
      @active = active
      @metadata = metadata
    end

    def call
      ApplicationRecord.transaction do
        entitlement = ProviderEntitlement.find_or_initialize_by(
          installation: @installation,
          provider_handle: @provider_handle,
          entitlement_key: @entitlement_key
        )
        entitlement.assign_attributes(
          window_kind: @window_kind,
          window_seconds: WINDOW_SECONDS_BY_KIND[@window_kind.to_s],
          quota_limit: @quota_limit,
          active: @active,
          metadata: @metadata
        )
        entitlement.save!

        AuditLog.record!(
          installation: @installation,
          actor: @actor,
          action: "provider_entitlement.upserted",
          subject: entitlement,
          metadata: {
            provider_handle: @provider_handle,
            entitlement_key: @entitlement_key,
          }
        )

        entitlement
      end
    end
  end
end
