module ProviderPolicies
  class Upsert
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, actor:, provider_handle:, enabled:, selection_defaults: {})
      @installation = installation
      @actor = actor
      @provider_handle = provider_handle
      @enabled = enabled
      @selection_defaults = selection_defaults
    end

    def call
      ApplicationRecord.transaction do
        policy = ProviderPolicy.find_or_initialize_by(
          installation: @installation,
          provider_handle: @provider_handle
        )
        ProviderCatalog::Assertions.assert_provider_exists!(
          record: policy,
          provider_handle: @provider_handle
        )
        policy.assign_attributes(
          enabled: @enabled,
          selection_defaults: @selection_defaults
        )
        policy.save!

        AuditLog.record!(
          installation: @installation,
          actor: @actor,
          action: "provider_policy.upserted",
          subject: policy,
          metadata: {
            provider_handle: @provider_handle,
          }
        )

        policy
      end
    end
  end
end
