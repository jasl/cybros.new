require "test_helper"

class Providers::CheckAvailabilityTest < ActiveSupport::TestCase
  test "returns missing credential when a credential-backed provider has no matching credential" do
    installation = create_installation!
    create_provider_entitlement!(installation: installation, provider_handle: "openrouter")

    result = Providers::CheckAvailability.call(
      installation: installation,
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      env: "test"
    )

    assert_equal false, result.usable?
    assert_equal "missing_credential", result.reason_key
  end

  test "returns policy disabled when installation policy disables the provider" do
    installation = create_installation!
    create_provider_entitlement!(installation: installation, provider_handle: "openrouter")
    create_provider_credential!(installation: installation, provider_handle: "openrouter", credential_kind: "api_key")
    ProviderPolicy.create!(
      installation: installation,
      provider_handle: "openrouter",
      enabled: false,
      selection_defaults: {}
    )

    result = Providers::CheckAvailability.call(
      installation: installation,
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      env: "test"
    )

    assert_equal false, result.usable?
    assert_equal "policy_disabled", result.reason_key
  end

  test "returns environment not allowed when the provider is not visible in the current environment" do
    installation = create_installation!
    create_provider_entitlement!(installation: installation, provider_handle: "dev")

    result = Providers::CheckAvailability.call(
      installation: installation,
      provider_handle: "dev",
      model_ref: "mock-model",
      env: "production"
    )

    assert_equal false, result.usable?
    assert_equal "environment_not_allowed", result.reason_key
  end

  test "returns usable when a credential-free provider has an active entitlement in the current environment" do
    installation = create_installation!
    create_provider_entitlement!(installation: installation, provider_handle: "dev")

    result = Providers::CheckAvailability.call(
      installation: installation,
      provider_handle: "dev",
      model_ref: "mock-model",
      env: "test"
    )

    assert result.usable?
    assert_nil result.reason_key
    assert_equal "shared_window", result.entitlement.entitlement_key
  end

  test "returns model disabled when the model exists but is disabled" do
    installation = create_installation!
    create_provider_entitlement!(installation: installation, provider_handle: "openrouter")
    create_provider_credential!(installation: installation, provider_handle: "openrouter", credential_kind: "api_key")

    disabled_catalog_definition = test_provider_catalog_definition.deep_dup
    disabled_catalog_definition[:providers][:openrouter][:models]["openai-gpt-5.4"][:enabled] = false
    disabled_catalog = build_test_provider_catalog_from(disabled_catalog_definition)

    result = Providers::CheckAvailability.call(
      installation: installation,
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      env: "test",
      catalog: disabled_catalog
    )

    assert_equal false, result.usable?
    assert_equal "model_disabled", result.reason_key
  end

  private

  def create_provider_entitlement!(installation:, provider_handle:)
    ProviderEntitlement.create!(
      installation: installation,
      provider_handle: provider_handle,
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )
  end

  def create_provider_credential!(installation:, provider_handle:, credential_kind:)
    ProviderCredential.create!(
      installation: installation,
      provider_handle: provider_handle,
      credential_kind: credential_kind,
      secret: "secret-#{provider_handle}",
      last_rotated_at: Time.current,
      metadata: {}
    )
  end
end
