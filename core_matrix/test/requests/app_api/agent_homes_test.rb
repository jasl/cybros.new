require "test_helper"

class AppApiAgentHomesTest < ActionDispatch::IntegrationTest
  test "shows materialized mounted workspaces without returning default workspace references" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])

    assert_no_difference(["WorkspaceAgent.count", "Workspace.count"]) do
      get "/app_api/agents/#{context[:agent].public_id}/home",
        headers: app_api_headers(session.plaintext_token)
    end

    assert_response :success

    response_body = response.parsed_body
    assert_equal "agent_home_show", response_body.fetch("method_id")
    assert_equal context[:agent].public_id, response_body.fetch("agent").fetch("agent_id")
    refute response_body.key?("default_workspace_ref")
    assert_equal [context[:workspace].public_id], response_body.fetch("workspaces").map { |item| item.fetch("workspace_id") }
    assert_equal context[:workspace_agent].public_id, response_body.fetch("workspaces").first.fetch("workspace_agents").first.fetch("workspace_agent_id")
    refute_includes response.body, %("#{context[:agent].id}")
  end

  test "returns not found for an agent the user cannot access" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    owner = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Owner"
    )
    hidden_agent = create_agent!(
      installation: installation,
      visibility: "private",
      owner_user: owner,
      provisioning_origin: "user_created",
      key: "hidden-agent",
      display_name: "Hidden Agent"
    )

    get "/app_api/agents/#{hidden_agent.public_id}/home",
      headers: app_api_headers(session.plaintext_token)

    assert_response :not_found
  end

  test "shows agent home even when there are no mounted workspaces yet" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: runtime,
      display_name: "Alpha Agent"
    )
    create_agent_connection!(installation: installation, agent: agent)

    get "/app_api/agents/#{agent.public_id}/home",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal agent.public_id, response.parsed_body.fetch("agent").fetch("agent_id")
    refute response.parsed_body.key?("default_workspace_ref")
    assert_equal [], response.parsed_body.fetch("workspaces")
  end

  test "does not return revoked mounts as launchable workspaces" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )

    get "/app_api/agents/#{context[:agent].public_id}/home",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal [], response.parsed_body.fetch("workspaces")
    refute response.parsed_body.key?("default_workspace_ref")
  end

  test "loads a materialized agent home within six SQL queries" do
    context = create_workspace_context!
    secondary_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      name: "Secondary Workspace"
    )
    create_workspace_agent!(
      installation: context[:installation],
      workspace: secondary_workspace,
      agent: context[:agent],
      default_execution_runtime: context[:execution_runtime]
    )
    session = create_session!(user: context[:user])

    assert_sql_query_count_at_most(6) do
      get "/app_api/agents/#{context[:agent].public_id}/home",
        headers: app_api_headers(session.plaintext_token)
    end

    assert_response :success
  end
end
