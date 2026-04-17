require "test_helper"

class AppApiAdminLLMProvidersTest < ActionDispatch::IntegrationTest
  test "lists catalog-backed providers even before overlay rows exist" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)

    get "/app_api/admin/llm_providers", headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "admin_llm_provider_index", response_body.fetch("method_id")

    providers = response_body.fetch("llm_providers")
    assert_equal ProviderCatalog::Registry.current.providers.keys.sort, providers.map { |provider| provider.fetch("provider_handle") }

    codex_provider = providers.find { |provider| provider.fetch("provider_handle") == "codex_subscription" }
    assert_equal "Codex Subscription", codex_provider.fetch("display_name")
    assert_equal "oauth_codex", codex_provider.fetch("credential_kind")
    assert_equal false, codex_provider.fetch("configured")
    assert_equal false, codex_provider.fetch("usable")
    assert_equal false, codex_provider.fetch("reauthorization_required")
  end

  test "shows a provider overlay without exposing plaintext secrets" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    ProviderPolicies::Upsert.call(
      installation: installation,
      actor: admin,
      provider_handle: "openai",
      enabled: false,
      selection_defaults: { "interactive" => "role:main" }
    )
    ProviderEntitlements::Upsert.call(
      installation: installation,
      actor: admin,
      provider_handle: "openai",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      quota_limit: 250_000,
      active: true,
      metadata: { "source" => "admin" }
    )
    ProviderCredentials::UpsertSecret.call(
      installation: installation,
      actor: admin,
      provider_handle: "openai",
      credential_kind: "api_key",
      secret: "sk-live-top-secret",
      metadata: { "label" => "primary" }
    )

    get "/app_api/admin/llm_providers/openai", headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "admin_llm_provider_show", response_body.fetch("method_id")

    provider = response_body.fetch("llm_provider")
    assert_equal "openai", provider.fetch("provider_handle")
    assert_equal false, provider.fetch("enabled")
    assert_equal true, provider.fetch("configured")
    assert_equal "configured", provider.fetch("credential_status")
    assert_equal({ "label" => "primary" }, provider.fetch("credential").fetch("metadata"))
    assert_equal false, provider.fetch("policy").fetch("enabled")
    assert_equal({ "interactive" => "role:main" }, provider.fetch("policy").fetch("selection_defaults"))
    assert_equal 1, provider.fetch("entitlements").length
    refute_includes response.body, "sk-live-top-secret"
  end

  test "updates provider enabled state through the provider resource" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)

    patch "/app_api/admin/llm_providers/openai",
      params: { enabled: false },
      as: :json,
      headers: app_api_headers(session.plaintext_token)

    assert_response :success

    assert_equal false, ProviderPolicy.find_by!(installation: installation, provider_handle: "openai").enabled
    assert_equal false, response.parsed_body.dig("llm_provider", "enabled")
  end

  test "updates api key credentials through the credential subresource without echoing the secret" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)

    patch "/app_api/admin/llm_providers/openrouter/credential",
      params: {
        secret: "sk-live-openrouter",
        metadata: { label: "shared" },
      },
      as: :json,
      headers: app_api_headers(session.plaintext_token)

    assert_response :success

    credential = ProviderCredential.find_by!(
      installation: installation,
      provider_handle: "openrouter",
      credential_kind: "api_key"
    )
    assert_equal "sk-live-openrouter", credential.secret
    assert_equal({ "label" => "shared" }, credential.metadata)
    assert_equal true, response.parsed_body.dig("llm_provider", "configured")
    refute_includes response.body, "sk-live-openrouter"
  end

  test "rejects direct credential writes for oauth codex providers" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)

    patch "/app_api/admin/llm_providers/codex_subscription/credential",
      params: { secret: "should-not-work" },
      as: :json,
      headers: app_api_headers(session.plaintext_token)

    assert_response :unprocessable_entity
    assert_equal "oauth credentials must use the codex device flow", response.parsed_body.fetch("error")
  end

  test "updates provider selection defaults through the policy subresource" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)

    patch "/app_api/admin/llm_providers/openai/policy",
      params: {
        selection_defaults: {
          interactive: "candidate:openai/gpt-5.4",
          automation: "role:main",
        },
      },
      as: :json,
      headers: app_api_headers(session.plaintext_token)

    assert_response :success

    policy = ProviderPolicy.find_by!(installation: installation, provider_handle: "openai")
    assert_equal(
      {
        "interactive" => "candidate:openai/gpt-5.4",
        "automation" => "role:main",
      },
      policy.selection_defaults
    )
    assert_equal(
      {
        "interactive" => "candidate:openai/gpt-5.4",
        "automation" => "role:main",
      },
      response.parsed_body.dig("llm_provider", "policy", "selection_defaults")
    )
  end

  test "replaces provider entitlements through the entitlements subresource" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    ProviderEntitlements::Upsert.call(
      installation: installation,
      actor: admin,
      provider_handle: "openai",
      entitlement_key: "old_window",
      window_kind: "calendar_day",
      quota_limit: 10_000,
      active: false,
      metadata: { "source" => "old" }
    )

    patch "/app_api/admin/llm_providers/openai/entitlements",
      params: {
        entitlements: [
          {
            entitlement_key: "shared_window",
            window_kind: "rolling_five_hours",
            quota_limit: 250_000,
            active: true,
            metadata: { source: "admin" },
          },
        ],
      },
      as: :json,
      headers: app_api_headers(session.plaintext_token)

    assert_response :success

    entitlements = ProviderEntitlement.where(installation: installation, provider_handle: "openai").order(:entitlement_key)
    assert_equal ["shared_window"], entitlements.pluck(:entitlement_key)
    assert_equal 250_000, entitlements.first.quota_limit
    assert entitlements.first.active?
    assert_equal ["shared_window"], response.parsed_body.dig("llm_provider", "entitlements").map { |item| item.fetch("entitlement_key") }
  end

  test "rejects non-admin access to llm providers" do
    installation = create_installation!
    member = create_user!(installation: installation, role: "member")
    session = create_session!(user: member)

    get "/app_api/admin/llm_providers", headers: app_api_headers(session.plaintext_token)

    assert_response :forbidden
    assert_equal "admin access is required", response.parsed_body.fetch("error")
  end

  test "queues an async connection test and exposes the latest succeeded result" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    ProviderEntitlements::Upsert.call(
      installation: installation,
      actor: admin,
      provider_handle: "openai",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      quota_limit: 250_000,
      active: true,
      metadata: {}
    )
    ProviderCredentials::UpsertSecret.call(
      installation: installation,
      actor: admin,
      provider_handle: "openai",
      credential_kind: "api_key",
      secret: "sk-openai",
      metadata: {}
    )

    original_dispatch = ProviderGateway::DispatchText.method(:call)
    ProviderGateway::DispatchText.singleton_class.define_method(:call) do |**_kwargs|
      ProviderGateway::DispatchText::Result.new(
        provider_result: nil,
        provider_request_id: "provider-request-123",
        content: "pong",
        usage: { "total_tokens" => 5 },
        duration_ms: 42
      )
    end

    assert_enqueued_with(job: ProviderConnectionChecks::ExecuteJob) do
      post "/app_api/admin/llm_providers/openai/test_connection",
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :accepted
    assert_equal "admin_llm_provider_test_connection", response.parsed_body.fetch("method_id")
    assert_equal "queued", response.parsed_body.dig("llm_provider", "connection_test", "status")

    perform_enqueued_jobs only: ProviderConnectionChecks::ExecuteJob

    get "/app_api/admin/llm_providers/openai", headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "succeeded", response.parsed_body.dig("llm_provider", "connection_test", "status")
    assert_equal "provider-request-123", response.parsed_body.dig("llm_provider", "connection_test", "result", "provider_request_id")
    assert_equal "candidate:openai/gpt-5.3-chat-latest", response.parsed_body.dig("llm_provider", "connection_test", "request", "selector")
  ensure
    ProviderGateway::DispatchText.singleton_class.define_method(:call, original_dispatch) if original_dispatch
  end

  test "persists the latest failed connection test result when the provider is unusable" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    ProviderCredentials::UpsertSecret.call(
      installation: installation,
      actor: admin,
      provider_handle: "openai",
      credential_kind: "api_key",
      secret: "sk-openai",
      metadata: {}
    )

    post "/app_api/admin/llm_providers/openai/test_connection",
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :accepted

    perform_enqueued_jobs only: ProviderConnectionChecks::ExecuteJob

    get "/app_api/admin/llm_providers/openai", headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "failed", response.parsed_body.dig("llm_provider", "connection_test", "status")
    assert_equal "missing_entitlement", response.parsed_body.dig("llm_provider", "connection_test", "failure", "reason_key")
  end
end
