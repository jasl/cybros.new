require "test_helper"

class AppApiWorkspacePoliciesTest < ActionDispatch::IntegrationTest
  test "shows user-facing workspace policy state with fenix capability baseline applied" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(
      installation: installation,
      key: "fenix",
      display_name: "Fenix",
      default_execution_runtime: runtime
    )
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      default_execution_runtime: runtime
    )

    get "/app_api/workspaces/#{workspace.public_id}/policy",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "workspace_policy_show", response.parsed_body.fetch("method_id")
    assert_equal workspace.public_id, response.parsed_body.fetch("workspace_id")
    assert_equal runtime.public_id, response.parsed_body.dig("workspace_policy", "default_execution_runtime_id")
    assert_includes response.parsed_body.dig("workspace_policy", "available_capabilities"), "supervision"
    refute_includes response.parsed_body.dig("workspace_policy", "available_capabilities"), "regenerate"
    refute_includes response.parsed_body.dig("workspace_policy", "available_capabilities"), "swipe"
  end

  test "updates disabled capabilities and default runtime and projects the policy into new conversations" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    runtime_a = create_execution_runtime!(installation: installation)
    runtime_b = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: runtime_a)
    create_execution_runtime_connection!(installation: installation, execution_runtime: runtime_b)
    agent = create_agent!(
      installation: installation,
      key: "builder",
      default_execution_runtime: runtime_a
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
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      default_execution_runtime: runtime_a
    )

    patch "/app_api/workspaces/#{workspace.public_id}/policy",
      params: {
        disabled_capabilities: ["side_chat"],
        default_execution_runtime_id: runtime_b.public_id,
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :success
    assert_equal "workspace_policy_update", response.parsed_body.fetch("method_id")
    assert_equal ["side_chat"], response.parsed_body.dig("workspace_policy", "disabled_capabilities")
    refute_includes response.parsed_body.dig("workspace_policy", "effective_capabilities"), "side_chat"
    refute_includes response.parsed_body.dig("workspace_policy", "effective_capabilities"), "control"
    assert_equal runtime_b.public_id, response.parsed_body.dig("workspace_policy", "default_execution_runtime_id")

    post "/app_api/conversations",
      params: {
        agent_id: agent.public_id,
        workspace_id: workspace.public_id,
        content: "Start work",
        selector: "candidate:codex_subscription/gpt-5.3-codex",
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :created

    turn = Turn.find_by_public_id!(response.parsed_body.fetch("turn_id"))
    conversation = Conversation.find_by_public_id!(response.parsed_body.dig("conversation", "conversation_id"))
    capability_policy = conversation.conversation_capability_policy
    assert_not_nil capability_policy
    assert_equal false, capability_policy.side_chat_enabled
    assert_equal false, capability_policy.control_enabled
    assert_equal runtime_b, turn.execution_runtime
    assert_equal runtime_b, workspace.reload.default_execution_runtime
  end

  test "rejects unknown capabilities" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])

    patch "/app_api/workspaces/#{context[:workspace].public_id}/policy",
      params: {
        disabled_capabilities: ["not-real"],
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :unprocessable_entity
    assert_equal "disabled_capabilities must be a subset of the available capabilities", response.parsed_body.fetch("error")
  end

  test "shows workspace policy when the workspace no longer has a matching binding row" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(
      installation: installation,
      key: "builder",
      default_execution_runtime: runtime
    )
    workspace = Workspace.create!(
      installation: installation,
      user: user,
      agent: agent,
      default_execution_runtime: runtime,
      name: "Detached Workspace",
      privacy: "private"
    )

    get "/app_api/workspaces/#{workspace.public_id}/policy",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal agent.public_id, response.parsed_body.dig("workspace_policy", "agent_id")
    assert_equal runtime.public_id, response.parsed_body.dig("workspace_policy", "default_execution_runtime_id")
  end

  test "rejects default runtime updates that target an inaccessible runtime" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    other_user = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Private Runtime Owner"
    )
    private_runtime = create_execution_runtime!(
      installation: context[:installation],
      visibility: "private",
      owner_user: other_user
    )
    create_execution_runtime_connection!(
      installation: context[:installation],
      execution_runtime: private_runtime
    )

    patch "/app_api/workspaces/#{context[:workspace].public_id}/policy",
      params: {
        default_execution_runtime_id: private_runtime.public_id,
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :not_found
    assert_equal context[:execution_runtime], context[:workspace].reload.default_execution_runtime
  end

  test "treats non-owned workspaces as not found" do
    context = create_workspace_context!
    other_user = create_user!(installation: context[:installation])
    session = create_session!(user: other_user)

    get "/app_api/workspaces/#{context[:workspace].public_id}/policy",
      headers: app_api_headers(session.plaintext_token)

    assert_response :not_found
  end
end
