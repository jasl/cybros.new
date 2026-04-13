require "test_helper"

class AppApiConversationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "creates a conversation from the conversation-first endpoint as pending execution" do
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

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      assert_difference(["Conversation.count", "Turn.count", "Message.count"], +1) do
        assert_no_difference("WorkflowRun.count") do
        post "/app_api/conversations",
          params: {
            agent_id: agent.public_id,
            content: "Start from conversations endpoint",
            selector: "candidate:codex_subscription/gpt-5.3-codex",
          },
          headers: app_api_headers(session.plaintext_token),
          as: :json
        end
      end
    end

    assert_response :created
    body = response.parsed_body
    title_job = enqueued_jobs.find { |job| job[:job].to_s == "Conversations::Metadata::BootstrapTitleJob" }
    assert title_job.present?
    assert_equal [body.dig("conversation", "conversation_id"), body.fetch("turn_id")], title_job[:args]
    assert_equal "conversation_create", body.fetch("method_id")
    assert_equal agent.public_id, body.dig("conversation", "agent_id")
    assert_equal execution_runtime.public_id, body.dig("conversation", "current_execution_runtime_id")
    assert_equal "ready", body.dig("conversation", "execution_continuity_state")
    assert body.dig("conversation", "current_execution_epoch_id").present?
    assert_equal I18n.t("conversations.defaults.untitled_title"), body.dig("conversation", "title")
    assert_equal "pending", body.fetch("execution_status")
    assert body.fetch("accepted_at").present?
    assert_equal "Start from conversations endpoint.", body.fetch("request_summary")
  end

  test "materializes the default workspace on first use" do
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

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      assert_difference(["UserAgentBinding.count", "Workspace.count", "Conversation.count", "Turn.count", "Message.count"], +1) do
        assert_no_difference("WorkflowRun.count") do
        post "/app_api/conversations",
          params: {
            agent_id: agent.public_id,
            content: "Help me start",
            selector: "candidate:codex_subscription/gpt-5.3-codex",
          },
          headers: app_api_headers(session.plaintext_token),
          as: :json
        end
      end
    end

    assert_response :created

    response_body = response.parsed_body
    title_job = enqueued_jobs.find { |job| job[:job].to_s == "Conversations::Metadata::BootstrapTitleJob" }
    assert title_job.present?
    assert_equal [response_body.dig("conversation", "conversation_id"), response_body.fetch("turn_id")], title_job[:args]
    assert_equal "conversation_create", response_body.fetch("method_id")
    assert_equal "Help me start", response_body.dig("message", "content")
    assert_equal true, response_body.dig("workspace", "is_default")
    assert_equal I18n.t("conversations.defaults.untitled_title"), response_body.dig("conversation", "title")
    assert_equal(
      "candidate:codex_subscription/gpt-5.3-codex",
      Turn.find_by_public_id!(response_body.fetch("turn_id")).workflow_bootstrap_payload.fetch("selector")
    )
    assert_equal "pending", response_body.fetch("execution_status")
  end

  test "allows overriding the execution runtime for the first turn" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    default_runtime = create_execution_runtime!(installation: installation)
    override_runtime = create_execution_runtime!(installation: installation)
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

    assert_enqueued_with(job: Conversations::Metadata::BootstrapTitleJob) do
      assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
        post "/app_api/conversations",
          params: {
            agent_id: agent.public_id,
            content: "Use the other runtime",
            selector: "candidate:codex_subscription/gpt-5.3-codex",
            execution_runtime_id: override_runtime.public_id,
          },
          headers: app_api_headers(session.plaintext_token),
          as: :json
      end
    end

    assert_response :created
    turn = Turn.find_by_public_id!(response.parsed_body.fetch("turn_id"))
    assert_equal override_runtime, turn.execution_runtime
    assert_equal I18n.t("conversations.defaults.untitled_title"), turn.conversation.reload.title
    assert turn.conversation.title_source_none?
  end

  test "rejects first-turn runtime overrides that are not accessible to the current user" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    owner = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Private Runtime Owner"
    )
    default_runtime = create_execution_runtime!(installation: installation)
    private_runtime = create_execution_runtime!(
      installation: installation,
      visibility: "private",
      owner_user: owner
    )
    create_execution_runtime_connection!(installation: installation, execution_runtime: default_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: private_runtime)
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

    assert_no_difference(["Conversation.count", "Turn.count", "Message.count", "WorkflowRun.count"]) do
      post "/app_api/conversations",
        params: {
          agent_id: agent.public_id,
          content: "Use a private runtime",
          execution_runtime_id: private_runtime.public_id,
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :not_found
  end

  test "creates a conversation from the conversation-first endpoint within sixty-two SQL queries" do
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

    assert_sql_query_count_at_most(62) do
      post "/app_api/conversations",
        params: {
          agent_id: agent.public_id,
          content: "Start from conversations endpoint",
          selector: "candidate:codex_subscription/gpt-5.3-codex",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json

      assert_response :created
      assert_equal "pending", response.parsed_body.fetch("execution_status")
    end
  end

  test "rejects conversation creation when the agent is no longer accessible to the signed-in user" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    replacement_owner = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Replacement Owner"
    )
    execution_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: execution_runtime)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: execution_runtime
    )
    create_agent_connection!(installation: installation, agent: agent)

    agent.update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: replacement_owner
    )

    assert_no_difference(["Conversation.count", "Turn.count", "Message.count", "WorkflowRun.count"]) do
      post "/app_api/conversations",
        params: {
          agent_id: agent.public_id,
          content: "Start a hidden conversation",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :not_found
  end
end
