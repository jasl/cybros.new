require "test_helper"

class ProviderCatalog::EffectiveCatalogTest < ActiveSupport::TestCase
  test "exposes static role candidates from the underlying catalog snapshot" do
    installation = create_installation!
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)

    assert_equal ["openai/gpt-5.4"], effective_catalog.role_candidates("planner")
  end

  test "filters role candidates by installation-scoped availability" do
    installation = create_installation!
    create_provider_entitlement!(installation:, provider_handle: "codex_subscription")
    create_provider_entitlement!(installation:, provider_handle: "openai")
    create_provider_credential!(installation:, provider_handle: "openai", credential_kind: "api_key")

    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation, env: "test")

    assert_equal ["openai/gpt-5.4"], effective_catalog.available_candidates("main")
  end

  test "exposes installation-scoped availability for an explicit candidate" do
    installation = create_installation!
    create_provider_entitlement!(installation:, provider_handle: "openrouter")

    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation, env: "test")
    result = effective_catalog.availability(provider_handle: "openrouter", model_ref: "openai-gpt-5.4")

    assert_equal false, result.usable?
    assert_equal "missing_credential", result.reason_key
  end

  test "resolves role selectors with fallback semantics" do
    installation = create_installation!
    create_provider_entitlement!(
      installation:,
      provider_handle: "codex_subscription",
      metadata: { "reservation_denied" => true }
    )
    create_provider_entitlement!(installation:, provider_handle: "openai")
    create_provider_credential!(installation:, provider_handle: "codex_subscription", credential_kind: "oauth_codex")
    create_provider_credential!(installation:, provider_handle: "openai", credential_kind: "api_key")

    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation, env: "test")
    result = effective_catalog.resolve_selector(selector: "role:main")

    assert result.usable?
    assert_equal "role:main", result.normalized_selector
    assert_equal "main", result.resolved_role_name
    assert_equal "openai", result.provider_handle
    assert_equal "gpt-5.4", result.model_ref
    assert_equal 1, result.fallback_count
    assert_equal "role_fallback_after_reservation", result.resolution_reason
  end

  test "explicit candidate selectors do not fall back to unrelated models" do
    installation = create_installation!
    create_provider_entitlement!(installation:, provider_handle: "openrouter")
    create_provider_entitlement!(installation:, provider_handle: "openai")
    create_provider_credential!(installation:, provider_handle: "openai", credential_kind: "api_key")

    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation, env: "test")
    result = effective_catalog.resolve_selector(selector: "candidate:openrouter/openai-gpt-5.4")

    assert_equal false, result.usable?
    assert_equal "candidate:openrouter/openai-gpt-5.4", result.normalized_selector
    assert_equal "missing_credential", result.reason_key
    assert_equal 0, result.fallback_count
  end

  test "role options expose selector metadata for UI menus" do
    installation = create_installation!
    create_provider_entitlement!(installation:, provider_handle: "openai")
    create_provider_credential!(installation:, provider_handle: "openai", credential_kind: "api_key")
    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)

    planner_option = effective_catalog.role_options.find { |entry| entry.fetch("role_name") == "planner" }

    assert_equal "role", planner_option.fetch("kind")
    assert_equal "role:planner", planner_option.fetch("selector")
    assert_equal "planner", planner_option.fetch("role_name")
    assert_equal ["openai/gpt-5.4"], planner_option.fetch("candidate_refs")
    assert_equal true, planner_option.fetch("usable")
    assert_equal "openai/gpt-5.4", planner_option.fetch("resolved_candidate_ref")
    assert_equal "role_primary", planner_option.fetch("resolution_reason")
  end

  test "candidate options expose labels and availability metadata for UI autocomplete" do
    installation = create_installation!
    create_provider_entitlement!(installation:, provider_handle: "openrouter")

    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation, env: "test")
    option = effective_catalog.candidate_options(query: "openrouter").find do |entry|
      entry.fetch("provider_handle") == "openrouter" && entry.fetch("model_ref") == "openai-gpt-5.4"
    end

    assert_equal "candidate", option.fetch("kind")
    assert_equal "candidate:openrouter/openai-gpt-5.4", option.fetch("selector")
    assert_equal "OpenRouter / OpenAI GPT-5.4", option.fetch("label")
    assert_equal "OpenRouter", option.fetch("provider_display_name")
    assert_equal "OpenAI GPT-5.4", option.fetch("model_display_name")
    assert_equal false, option.fetch("usable")
    assert_equal "missing_credential", option.fetch("reason_key")
  end

  test "selector options combine role and candidate entries for UI pickers" do
    installation = create_installation!
    create_provider_entitlement!(installation:, provider_handle: "openai")
    create_provider_credential!(installation:, provider_handle: "openai", credential_kind: "api_key")

    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)
    options = effective_catalog.selector_options(query: "gpt-5.4")

    assert_includes options.map { |entry| entry.fetch("selector") }, "role:planner"
    assert_includes options.map { |entry| entry.fetch("selector") }, "candidate:openai/gpt-5.4"
  end

  test "selector option hydrates normalized role selectors for UI state" do
    installation = create_installation!
    create_provider_entitlement!(installation:, provider_handle: "openai")
    create_provider_credential!(installation:, provider_handle: "openai", credential_kind: "api_key")

    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation)
    option = effective_catalog.selector_option(selector: "planner")

    assert_equal "role", option.fetch("kind")
    assert_equal "role:planner", option.fetch("selector")
    assert_equal "planner", option.fetch("label")
    assert_equal true, option.fetch("usable")
    assert_equal "openai/gpt-5.4", option.fetch("resolved_candidate_ref")
  end

  test "selector option hydrates normalized explicit candidates for UI state" do
    installation = create_installation!
    create_provider_entitlement!(installation:, provider_handle: "openrouter")

    effective_catalog = ProviderCatalog::EffectiveCatalog.new(installation: installation, env: "test")
    option = effective_catalog.selector_option(selector: "openrouter/openai-gpt-5.4")

    assert_equal "candidate", option.fetch("kind")
    assert_equal "candidate:openrouter/openai-gpt-5.4", option.fetch("selector")
    assert_equal "OpenRouter / OpenAI GPT-5.4", option.fetch("label")
    assert_equal false, option.fetch("usable")
    assert_equal "missing_credential", option.fetch("reason_key")
  end

  private

  def create_provider_entitlement!(installation:, provider_handle:, metadata: {})
    ProviderEntitlement.create!(
      installation: installation,
      provider_handle: provider_handle,
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: metadata
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
