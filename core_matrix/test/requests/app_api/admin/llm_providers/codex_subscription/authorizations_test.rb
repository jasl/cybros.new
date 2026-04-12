require "test_helper"

class AppApiAdminLlmProvidersCodexSubscriptionAuthorizationsTest < ActionDispatch::IntegrationTest
  test "routes only the codex subscription singular authorization resource" do
    recognized = Rails.application.routes.recognize_path(
      "/app_api/admin/llm_providers/codex_subscription/authorization",
      method: :get
    )

    assert_equal "app_api/admin/llm_providers/codex_subscription/authorizations", recognized.fetch(:controller)
    assert_equal "show", recognized.fetch(:action)

    recognized = Rails.application.routes.recognize_path(
      "/app_api/admin/llm_providers/codex_subscription/authorization",
      method: :post
    )

    assert_equal "app_api/admin/llm_providers/codex_subscription/authorizations", recognized.fetch(:controller)
    assert_equal "create", recognized.fetch(:action)

    recognized = Rails.application.routes.recognize_path(
      "/app_api/admin/llm_providers/codex_subscription/authorization",
      method: :delete
    )

    assert_equal "app_api/admin/llm_providers/codex_subscription/authorizations", recognized.fetch(:controller)
    assert_equal "destroy", recognized.fetch(:action)

    recognized = Rails.application.routes.recognize_path(
      "/app_api/admin/llm_providers/codex_subscription/authorization/callback",
      method: :get
    )

    assert_equal "app_api/admin/llm_providers/codex_subscription/authorizations", recognized.fetch(:controller)
    assert_equal "callback", recognized.fetch(:action)

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/app_api/admin/llm_providers/openai/authorization",
        method: :post
      )
    end
  end

  test "creates a codex subscription authorization session and returns an authorization url" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)

    post "/app_api/admin/llm_providers/codex_subscription/authorization",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "admin_codex_subscription_authorization_create", response_body.fetch("method_id")
    authorization = response_body.fetch("authorization")
    assert_equal "codex_subscription", authorization.fetch("provider_handle")
    assert_equal "pending", authorization.fetch("status")
    assert_match(%r{\Ahttps?://}, authorization.fetch("authorization_url"))
    assert_nil authorization["access_token"]
    assert_nil authorization["refresh_token"]
  end

  test "returns not found when codex subscription is disabled in the effective catalog" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog_definition[:providers][:codex_subscription][:enabled] = false
    disabled_catalog = build_test_provider_catalog_from(catalog_definition)

    with_stubbed_provider_catalog(disabled_catalog) do
      get "/app_api/admin/llm_providers/codex_subscription/authorization",
        headers: app_api_headers(session.plaintext_token)
    end

    assert_response :not_found
  end

  test "shows current codex subscription authorization state without exposing tokens" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    authorization_session = ProviderAuthorizationSession.issue!(
      installation: installation,
      provider_handle: "codex_subscription",
      issued_by_user: admin,
      expires_at: 15.minutes.from_now
    )
    ProviderCredential.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "access-token-1",
      refresh_token: "refresh-token-1",
      expires_at: 2.hours.from_now,
      last_rotated_at: Time.current,
      metadata: {}
    )

    get "/app_api/admin/llm_providers/codex_subscription/authorization",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    authorization = response.parsed_body.fetch("authorization")
    assert_equal "pending", authorization.fetch("status")
    assert_equal true, authorization.fetch("configured")
    assert_nil authorization["access_token"]
    assert_nil authorization["refresh_token"]
    assert_equal true, authorization.fetch("usable")
    assert authorization_session.reload.active?
  end

  test "destroy revokes pending sessions and removes oauth credentials" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    pending_session = ProviderAuthorizationSession.issue!(
      installation: installation,
      provider_handle: "codex_subscription",
      issued_by_user: admin,
      expires_at: 15.minutes.from_now
    )
    ProviderCredential.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "access-token-1",
      refresh_token: "refresh-token-1",
      expires_at: 2.hours.from_now,
      last_rotated_at: Time.current,
      metadata: {}
    )

    delete "/app_api/admin/llm_providers/codex_subscription/authorization",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "missing", response.parsed_body.dig("authorization", "status")
    assert_predicate pending_session.reload, :revoked?
    assert_nil ProviderCredential.find_by(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex"
    )
  end

  test "callback completes the authorization session and persists the oauth credential" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    authorization_session = ProviderAuthorizationSession.issue!(
      installation: installation,
      provider_handle: "codex_subscription",
      issued_by_user: admin,
      expires_at: 15.minutes.from_now
    )
    original_exchange = LLMProviders::CodexSubscription::OAuthClient.method(:exchange_code)
    LLMProviders::CodexSubscription::OAuthClient.singleton_class.define_method(:exchange_code) do |**_kwargs|
      {
        access_token: "access-token-1",
        refresh_token: "refresh-token-1",
        expires_at: 2.hours.from_now,
      }
    end

    get "/app_api/admin/llm_providers/codex_subscription/authorization/callback",
      params: {
        state: authorization_session.plaintext_state,
        code: "oauth-code-123",
      }

    assert_response :success
    assert_match(/authorization completed/i, response.body)
    assert_equal "completed", authorization_session.reload.status
    credential = ProviderCredential.find_by!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex"
    )
    assert_equal "access-token-1", credential.access_token
    assert_equal "refresh-token-1", credential.refresh_token
  ensure
    LLMProviders::CodexSubscription::OAuthClient.singleton_class.define_method(:exchange_code, original_exchange) if original_exchange
  end

  test "callback returns unprocessable entity for an invalid state" do
    get "/app_api/admin/llm_providers/codex_subscription/authorization/callback",
      params: {
        state: "not-a-real-state",
        code: "oauth-code-123",
      }

    assert_response :unprocessable_entity
  end
end
