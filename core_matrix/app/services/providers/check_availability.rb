module Providers
  class CheckAvailability
    Result = Struct.new(:usable, :reason_key, :provider_handle, :model_ref, :entitlement, keyword_init: true) do
      def usable?
        usable
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, provider_handle:, model_ref:, env: Rails.env, catalog: ProviderCatalog::Load.call)
      @installation = installation
      @provider_handle = provider_handle.to_s
      @model_ref = model_ref.to_s
      @env = env.to_s
      @catalog = catalog
    end

    def call
      provider = catalog.providers[@provider_handle]
      return unavailable("unknown_provider") if provider.blank?

      model = provider.fetch(:models)[@model_ref]
      return unavailable("unknown_model") if model.blank?
      return unavailable("provider_disabled") unless provider.fetch(:enabled)
      return unavailable("environment_not_allowed") unless provider.fetch(:environments).include?(@env)
      return unavailable("policy_disabled") if policy_disabled?

      entitlement = active_entitlement
      return unavailable("missing_entitlement") if entitlement.blank?

      if provider.fetch(:requires_credential) && matching_credential(provider.fetch(:credential_kind)).blank?
        return unavailable("missing_credential")
      end

      Result.new(
        usable: true,
        reason_key: nil,
        provider_handle: @provider_handle,
        model_ref: @model_ref,
        entitlement: entitlement
      )
    rescue KeyError
      unavailable("unknown_model")
    end

    private

    attr_reader :catalog

    def policy_disabled?
      ProviderPolicy.find_by(installation: @installation, provider_handle: @provider_handle)&.enabled == false
    end

    def active_entitlement
      ProviderEntitlement.where(
        installation: @installation,
        provider_handle: @provider_handle,
        active: true
      ).order(:id).first
    end

    def matching_credential(credential_kind)
      ProviderCredential.find_by(
        installation: @installation,
        provider_handle: @provider_handle,
        credential_kind: credential_kind
      )
    end

    def unavailable(reason_key)
      Result.new(
        usable: false,
        reason_key: reason_key,
        provider_handle: @provider_handle,
        model_ref: @model_ref,
        entitlement: nil
      )
    end
  end
end
