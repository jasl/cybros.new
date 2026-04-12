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
end
