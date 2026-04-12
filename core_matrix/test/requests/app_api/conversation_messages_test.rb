require "test_helper"

class AppApiConversationMessagesTest < ActionDispatch::IntegrationTest
  test "appends a user message through the app api" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_no_difference(["Workspace.count", "Conversation.count"]) do
      assert_enqueued_with(job: Workflows::ExecuteNodeJob) do
        assert_difference(["Turn.count", "Message.count", "WorkflowRun.count"], +1) do
          post "/app_api/conversations/#{conversation.public_id}/messages",
            params: {
              content: "Follow up",
            },
            headers: app_api_headers(session.plaintext_token),
            as: :json
        end
      end
    end

    assert_response :created

    response_body = response.parsed_body
    assert_equal "conversation_message_create", response_body.fetch("method_id")
    assert_equal conversation.public_id, response_body.fetch("conversation_id")
    assert_equal "Follow up", response_body.dig("message", "content")
  end

  test "allows overriding the execution runtime for a follow-up turn" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    default_runtime = create_execution_runtime!(installation: installation)
    override_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: default_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: override_runtime)
    agent = create_agent!(installation: installation, default_execution_runtime: default_runtime)
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
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      default_execution_runtime: default_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace: workspace, agent: agent)

    post "/app_api/conversations/#{conversation.public_id}/messages",
      params: {
        content: "Follow up",
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
