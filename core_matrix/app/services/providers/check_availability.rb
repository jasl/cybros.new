module Providers
  class CheckAvailability
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, provider_handle:, model_ref:, env: Rails.env, catalog: nil)
      @installation = installation
      @provider_handle = provider_handle.to_s
      @model_ref = model_ref.to_s
      @env = env.to_s
      @catalog = catalog
    end

    def call
      ProviderCatalog::EffectiveCatalog.new(
        installation: @installation,
        env: @env,
        catalog: @catalog
      ).availability(
        provider_handle: @provider_handle,
        model_ref: @model_ref
      )
    end
  end
end
