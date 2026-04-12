require "test_helper"

class AppApiAgentConversationsTest < ActionDispatch::IntegrationTest
  test "creates a conversation from an agent and materializes the default workspace on first use" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    execution_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: execution_runtime)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: execution_runtime
    )
    create_agent_connection!(installation: installation, agent: agent)
    ProviderEntitlement.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )
    ProviderCredential.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "oauth-codex-access-token",
      refresh_token: "oauth-codex-refresh-token",
      expires_at: 2.hours.from_now,
      last_rotated_at: Time.current,
      metadata: {}
    )

    assert_enqueued_with(job: Workflows::ExecuteNodeJob) do
      assert_difference(["UserAgentBinding.count", "Workspace.count", "Conversation.count", "Turn.count", "Message.count", "WorkflowRun.count"], +1) do
        post "/app_api/agents/#{agent.public_id}/conversations",
          params: {
            content: "Help me start",
            selector: "candidate:codex_subscription/gpt-5.3-codex",
          },
          headers: app_api_headers(session.plaintext_token),
          as: :json
      end
    end

    assert_response :created

    response_body = response.parsed_body
    assert_equal "agent_conversation_create", response_body.fetch("method_id")
    assert_equal agent.public_id, response_body.fetch("agent_id")
    assert_equal "Help me start", response_body.dig("message", "content")
    assert_equal true, response_body.dig("workspace", "is_default")
    assert_equal(
      "candidate:codex_subscription/gpt-5.3-codex",
      Turn.find_by_public_id!(response_body.fetch("turn_id")).resolved_model_selection_snapshot.fetch("normalized_selector")
    )
  end

  test "allows overriding the execution runtime for the first turn" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    default_runtime = create_execution_runtime!(installation: installation)
    override_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: default_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: override_runtime)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: default_runtime
    )
    create_agent_connection!(installation: installation, agent: agent)
    ProviderEntitlement.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )
    ProviderCredential.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "oauth-codex-access-token",
      refresh_token: "oauth-codex-refresh-token",
      expires_at: 2.hours.from_now,
      last_rotated_at: Time.current,
      metadata: {}
    )

    post "/app_api/agents/#{agent.public_id}/conversations",
      params: {
        content: "Use the other runtime",
        selector: "candidate:codex_subscription/gpt-5.3-codex",
        execution_runtime_id: override_runtime.public_id,
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :created
    assert_equal(
      override_runtime,
      Turn.find_by_public_id!(response.parsed_body.fetch("turn_id")).execution_runtime
    )
  end
end
