module ProviderConnectionChecks
  class UpsertLatest
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, actor:, provider_handle:, requested_at: Time.current)
      @installation = installation
      @actor = actor
      @provider_handle = provider_handle.to_s
      @requested_at = requested_at
    end

    def call
      ApplicationRecord.transaction do
        connection_check = ProviderConnectionCheck.find_or_initialize_by(
          installation: @installation,
          provider_handle: @provider_handle
        )
        ProviderCatalog::Assertions.assert_provider_exists!(
          record: connection_check,
          provider_handle: @provider_handle
        )
        connection_check.assign_attributes(
          requested_by_user: @actor,
          lifecycle_state: "queued",
          queued_at: @requested_at,
          started_at: nil,
          finished_at: nil,
          request_payload: { "selector" => selector },
          result_payload: {},
          failure_payload: {}
        )
        connection_check.save!

        AuditLog.record!(
          installation: @installation,
          actor: @actor,
          action: "provider_connection_test.requested",
          subject: connection_check,
          metadata: {
            provider_handle: @provider_handle,
            selector: selector,
          }
        )

        connection_check
      end
    end

    private

    def selector
      @selector ||= begin
        selection_defaults = ProviderPolicy.find_by(
          installation: @installation,
          provider_handle: @provider_handle
        )&.selection_defaults || {}
        preferred_selector = selection_defaults["interactive"].presence
        return preferred_selector if preferred_selector.present?

        provider_definition = ProviderCatalog::Registry.current.provider(@provider_handle)
        model_ref = provider_definition.fetch(:models).keys.map(&:to_s).sort.first
        raise ArgumentError, "provider has no candidate models to test" if model_ref.blank?

        "candidate:#{@provider_handle}/#{model_ref}"
      end
    end
  end
end
