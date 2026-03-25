require "test_helper"

class ProviderCatalogBootFlowTest < ActionDispatch::IntegrationTest
  self.uses_real_provider_catalog = true

  test "the shipped provider catalog is boot-loadable" do
    catalog = ProviderCatalog::Load.call

    assert catalog.providers.present?
    assert catalog.model_roles.present?
    assert_equal true, catalog.model("openai", "gpt-5.4").fetch(:enabled)
  end
end
