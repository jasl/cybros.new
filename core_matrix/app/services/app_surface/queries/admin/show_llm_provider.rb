module AppSurface
  module Queries
    module Admin
      class ShowLLMProvider
        def self.call(...)
          new(...).call
        end

        def initialize(installation:, provider_handle:)
          @installation = installation
          @provider_handle = provider_handle.to_s
          @effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)
        end

        def call
          AppSurface::Presenters::LLMProviderPresenter.call(
            effective_catalog: @effective_catalog,
            provider_handle: @provider_handle,
            provider_definition: provider_definition,
            policy: ProviderPolicy.find_by(installation: @installation, provider_handle: @provider_handle),
            credential: ProviderCredential.find_by(installation: @installation, provider_handle: @provider_handle),
            entitlements: ProviderEntitlement.where(installation: @installation, provider_handle: @provider_handle),
            connection_check: ProviderConnectionCheck.find_by(installation: @installation, provider_handle: @provider_handle)
          )
        end

        private

        def provider_definition
          @effective_catalog.provider(@provider_handle)
        rescue KeyError
          raise ActiveRecord::RecordNotFound, "Couldn't find LLM provider"
        end
      end
    end
  end
end
