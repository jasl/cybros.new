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
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      default_execution_runtime: runtime,
      config: {},
      name: "Default Config Workspace",
      privacy: "private"
    )

    get "/app_api/workspaces/#{workspace.public_id}/policy",
      params: {
        workspace_agent_id: workspace.primary_workspace_agent.public_id,
      },
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "workspace_policy_show", response.parsed_body.fetch("method_id")
    assert_equal workspace.public_id, response.parsed_body.fetch("workspace_id")
    assert_equal workspace.primary_workspace_agent.public_id, response.parsed_body.dig("workspace_policy", "workspace_agent_id")
    assert_equal runtime.public_id, response.parsed_body.dig("workspace_policy", "default_execution_runtime_id")
    assert_equal "embedded_only", response.parsed_body.dig("workspace_policy", "features", "title_bootstrap", "strategy")
    assert_equal "runtime_first", response.parsed_body.dig("workspace_policy", "features", "prompt_compaction", "strategy")
    refute response.parsed_body.fetch("workspace_policy").key?("metadata")
    assert_includes response.parsed_body.dig("workspace_policy", "available_capabilities"), "supervision"
    refute_includes response.parsed_body.dig("workspace_policy", "available_capabilities"), "regenerate"
    refute_includes response.parsed_body.dig("workspace_policy", "available_capabilities"), "swipe"
  end

  test "updates disabled capabilities, default runtime, and resolved workspace features with partial merge semantics" do
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
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      default_execution_runtime: runtime_a,
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "disabled",
          },
          "prompt_compaction" => {
            "strategy" => "disabled",
          },
        },
      },
      name: "Policy Workspace",
      privacy: "private"
    )

    patch "/app_api/workspaces/#{workspace.public_id}/policy",
      params: {
        workspace_agent_id: workspace.primary_workspace_agent.public_id,
        disabled_capabilities: ["side_chat"],
        default_execution_runtime_id: runtime_b.public_id,
        features: {
          title_bootstrap: {
            strategy: "runtime_required",
          },
          prompt_compaction: {
            strategy: "embedded_only",
          },
        },
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :success
    assert_equal "workspace_policy_update", response.parsed_body.fetch("method_id")
    assert_equal ["side_chat"], response.parsed_body.dig("workspace_policy", "disabled_capabilities")
    assert_equal "runtime_required", response.parsed_body.dig("workspace_policy", "features", "title_bootstrap", "strategy")
    assert_equal "embedded_only", response.parsed_body.dig("workspace_policy", "features", "prompt_compaction", "strategy")
    refute_includes response.parsed_body.dig("workspace_policy", "effective_capabilities"), "side_chat"
    refute_includes response.parsed_body.dig("workspace_policy", "effective_capabilities"), "control"
    assert_equal runtime_b.public_id, response.parsed_body.dig("workspace_policy", "default_execution_runtime_id")
    assert_equal ["side_chat"], workspace.reload.disabled_capabilities
    assert_equal "runtime_required", workspace.reload.feature_config("title_bootstrap").fetch("strategy")
    assert_equal "embedded_only", workspace.reload.feature_config("prompt_compaction").fetch("strategy")

    post "/app_api/conversations",
      params: {
        workspace_agent_id: workspace.primary_workspace_agent.public_id,
        workspace_id: workspace.public_id,
        content: "Start work",
        selector: "candidate:codex_subscription/gpt-5.3-codex",
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :created

    turn = Turn.find_by_public_id!(response.parsed_body.fetch("turn_id"))
    conversation = Conversation.find_by_public_id!(response.parsed_body.dig("conversation", "conversation_id"))
    refute_respond_to conversation, :conversation_capability_policy
    assert_includes Conversation.attribute_names, "supervision_enabled"
    assert_includes Conversation.attribute_names, "side_chat_enabled"
    assert_includes Conversation.attribute_names, "control_enabled"
    assert_equal true, conversation.supervision_enabled
    assert_equal false, conversation.side_chat_enabled
    assert_equal false, conversation.control_enabled
    assert_equal runtime_b, turn.execution_runtime
    assert_equal runtime_b, workspace.reload.default_execution_runtime
  end

  test "rejects invalid title bootstrap strategies" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])

    patch "/app_api/workspaces/#{context[:workspace].public_id}/policy",
      params: {
        workspace_agent_id: context[:workspace_agent].public_id,
        features: {
          title_bootstrap: {
            strategy: "manual_only",
          },
        },
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :unprocessable_entity
    assert_equal "features.title_bootstrap.strategy must be one of disabled, embedded_only, runtime_first, runtime_required", response.parsed_body.fetch("error")
  end

  test "rejects invalid prompt compaction strategies" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])

    patch "/app_api/workspaces/#{context[:workspace].public_id}/policy",
      params: {
        workspace_agent_id: context[:workspace_agent].public_id,
        features: {
          prompt_compaction: {
            strategy: "manual_only",
          },
        },
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :unprocessable_entity
    assert_equal "features.prompt_compaction.strategy must be one of disabled, embedded_only, runtime_first, runtime_required", response.parsed_body.fetch("error")
  end

  test "rejects unknown capabilities" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])

    patch "/app_api/workspaces/#{context[:workspace].public_id}/policy",
      params: {
        workspace_agent_id: context[:workspace_agent].public_id,
        disabled_capabilities: ["not-real"],
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :unprocessable_entity
    assert_equal "disabled_capabilities must be a subset of the available capabilities", response.parsed_body.fetch("error")
  end

  test "shows workspace policy from workspace-owned attributes" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(
      installation: installation,
      key: "builder",
      default_execution_runtime: runtime
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      default_execution_runtime: runtime,
      disabled_capabilities: ["side_chat"],
      name: "Detached Workspace",
      privacy: "private"
    )

    get "/app_api/workspaces/#{workspace.public_id}/policy",
      params: {
        workspace_agent_id: workspace.primary_workspace_agent.public_id,
      },
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal agent.public_id, response.parsed_body.dig("workspace_policy", "agent_id")
    assert_equal workspace.primary_workspace_agent.public_id, response.parsed_body.dig("workspace_policy", "workspace_agent_id")
    assert_equal runtime.public_id, response.parsed_body.dig("workspace_policy", "default_execution_runtime_id")
    assert_equal ["side_chat"], response.parsed_body.dig("workspace_policy", "disabled_capabilities")
    assert_equal "embedded_only", response.parsed_body.dig("workspace_policy", "features", "title_bootstrap", "strategy")
    assert_equal "runtime_first", response.parsed_body.dig("workspace_policy", "features", "prompt_compaction", "strategy")
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
        workspace_agent_id: context[:workspace_agent].public_id,
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
      params: {
        workspace_agent_id: context[:workspace_agent].public_id,
      },
      headers: app_api_headers(session.plaintext_token)

    assert_response :not_found
  end

  test "shows workspace policy within eight SQL queries" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(
      installation: installation,
      key: "fenix",
      default_execution_runtime: runtime
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      default_execution_runtime: runtime
    )
    workspace_agent_id = workspace.primary_workspace_agent.public_id

    assert_sql_query_count_at_most(8) do
      get "/app_api/workspaces/#{workspace.public_id}/policy",
        params: {
          workspace_agent_id: workspace_agent_id,
        },
        headers: app_api_headers(session.plaintext_token)
    end

    assert_response :success
  end

  test "updates the requested workspace agent instead of the primary mount" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    primary_runtime = create_execution_runtime!(installation: installation, display_name: "Primary Runtime")
    secondary_runtime = create_execution_runtime!(installation: installation, display_name: "Secondary Runtime")
    override_runtime = create_execution_runtime!(installation: installation, display_name: "Override Runtime")
    create_execution_runtime_connection!(installation: installation, execution_runtime: primary_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: secondary_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: override_runtime)
    primary_agent = create_agent!(installation: installation, key: "primary", default_execution_runtime: primary_runtime)
    secondary_agent = create_agent!(installation: installation, key: "secondary", default_execution_runtime: secondary_runtime)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: primary_agent,
      default_execution_runtime: primary_runtime,
      name: "Multi Mount Policy Workspace",
      privacy: "private"
    )
    secondary_workspace_agent = create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: secondary_agent,
      default_execution_runtime: secondary_runtime
    )

    patch "/app_api/workspaces/#{workspace.public_id}/policy",
      params: {
        workspace_agent_id: secondary_workspace_agent.public_id,
        default_execution_runtime_id: override_runtime.public_id,
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :success
    assert_equal secondary_workspace_agent.public_id, response.parsed_body.dig("workspace_policy", "workspace_agent_id")
    assert_equal secondary_agent.public_id, response.parsed_body.dig("workspace_policy", "agent_id")
    assert_equal override_runtime.public_id, response.parsed_body.dig("workspace_policy", "default_execution_runtime_id")
    assert_equal primary_runtime, workspace.reload.primary_workspace_agent.default_execution_runtime
    assert_equal override_runtime, secondary_workspace_agent.reload.default_execution_runtime
  end

  test "shows the requested non-primary workspace agent policy" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    primary_runtime = create_execution_runtime!(installation: installation, display_name: "Primary Runtime")
    secondary_runtime = create_execution_runtime!(installation: installation, display_name: "Secondary Runtime")
    create_execution_runtime_connection!(installation: installation, execution_runtime: primary_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: secondary_runtime)
    primary_agent = create_agent!(installation: installation, key: "primary", default_execution_runtime: primary_runtime)
    secondary_agent = create_agent!(installation: installation, key: "secondary", default_execution_runtime: secondary_runtime)
    primary_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: primary_agent,
      reflected_surface: {
        "workspace_capabilities" => ["supervision"],
      }
    )
    secondary_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: secondary_agent,
      reflected_surface: {
        "workspace_capabilities" => ["supervision", "side_chat", "control"],
      }
    )
    primary_agent.update!(
      current_agent_definition_version: primary_definition_version,
      published_agent_definition_version: primary_definition_version
    )
    secondary_agent.update!(
      current_agent_definition_version: secondary_definition_version,
      published_agent_definition_version: secondary_definition_version
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: primary_agent,
      default_execution_runtime: primary_runtime,
      name: "Multi Mount Policy Read Workspace",
      privacy: "private"
    )
    secondary_workspace_agent = create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: secondary_agent,
      default_execution_runtime: secondary_runtime
    )

    get "/app_api/workspaces/#{workspace.public_id}/policy",
      params: {
        workspace_agent_id: secondary_workspace_agent.public_id,
      },
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal secondary_workspace_agent.public_id, response.parsed_body.dig("workspace_policy", "workspace_agent_id")
    assert_equal secondary_agent.public_id, response.parsed_body.dig("workspace_policy", "agent_id")
    assert_equal secondary_runtime.public_id, response.parsed_body.dig("workspace_policy", "default_execution_runtime_id")
    assert_equal %w[supervision side_chat control], response.parsed_body.dig("workspace_policy", "available_capabilities")
    assert_equal %w[supervision side_chat control], response.parsed_body.dig("workspace_policy", "effective_capabilities")
  end
end
