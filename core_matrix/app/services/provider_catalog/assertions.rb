module ProviderCatalog
  module Assertions
    module_function

    def assert_provider_exists!(record:, provider_handle:, attribute: :provider_handle, effective_catalog: ProviderCatalog::EffectiveCatalog.new)
      effective_catalog.provider(provider_handle)
    rescue KeyError
      record.errors.add(attribute, "must exist in the provider catalog")
      raise ActiveRecord::RecordInvalid, record
    end

    def assert_model_exists!(
      record:,
      provider_handle:,
      model_ref:,
      provider_attribute: :provider_handle,
      model_attribute: :model_ref,
      effective_catalog: ProviderCatalog::EffectiveCatalog.new
    )
      assert_provider_exists!(
        record: record,
        provider_handle: provider_handle,
        attribute: provider_attribute,
        effective_catalog: effective_catalog
      )

      effective_catalog.model(provider_handle, model_ref)
    rescue KeyError
      record.errors.add(model_attribute, "must exist in the provider catalog")
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
