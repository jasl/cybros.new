module AppSurface
  module Queries
    module Admin
      class ListLLMProviders
        def self.call(...)
          new(...).call
        end

        def initialize(installation:)
          @installation = installation
          @effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)
        end

        def call
          overlay_policies = ProviderPolicy.where(installation: @installation).index_by(&:provider_handle)
          overlay_credentials = ProviderCredential.where(installation: @installation).index_by(&:provider_handle)
          overlay_entitlements = ProviderEntitlement.where(installation: @installation).group_by(&:provider_handle)
          connection_checks = ProviderConnectionCheck.where(installation: @installation).index_by(&:provider_handle)

          ProviderCatalog::Registry.current.providers.keys.sort.map do |provider_handle|
            provider_definition = @effective_catalog.provider(provider_handle)
            AppSurface::Presenters::LLMProviderPresenter.call(
              effective_catalog: @effective_catalog,
              provider_handle: provider_handle,
              provider_definition: provider_definition,
              policy: overlay_policies[provider_handle],
              credential: overlay_credentials[provider_handle],
              entitlements: overlay_entitlements.fetch(provider_handle, []),
              connection_check: connection_checks[provider_handle]
            )
          end
        end
      end
    end
  end
end
