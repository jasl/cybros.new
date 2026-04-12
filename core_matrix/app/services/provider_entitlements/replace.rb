module ProviderEntitlements
  class Replace
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, actor:, provider_handle:, entitlements:)
      @installation = installation
      @actor = actor
      @provider_handle = provider_handle
      @entitlements = Array(entitlements).map { |entry| entry.deep_stringify_keys }
    end

    def call
      ApplicationRecord.transaction do
        assert_provider_exists!

        existing = ProviderEntitlement.where(
          installation: @installation,
          provider_handle: @provider_handle
        ).index_by(&:entitlement_key)
        keep_keys = @entitlements.map { |entry| entry.fetch("entitlement_key") }.uniq

        existing.each_value do |entitlement|
          next if keep_keys.include?(entitlement.entitlement_key)

          entitlement.destroy!
        end

        @entitlements.each do |entry|
          ProviderEntitlements::Upsert.call(
            installation: @installation,
            actor: @actor,
            provider_handle: @provider_handle,
            entitlement_key: entry.fetch("entitlement_key"),
            window_kind: entry.fetch("window_kind"),
            quota_limit: entry.fetch("quota_limit"),
            active: entry.fetch("active"),
            metadata: entry.fetch("metadata", {})
          )
        end

        ProviderEntitlement.where(
          installation: @installation,
          provider_handle: @provider_handle
        ).order(:entitlement_key)
      end
    end

    private

    def assert_provider_exists!
      ProviderCatalog::Assertions.assert_provider_exists!(
        record: ProviderEntitlement.new(installation: @installation),
        provider_handle: @provider_handle
      )
    end
  end
end
