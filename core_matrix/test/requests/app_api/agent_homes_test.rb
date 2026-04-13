require "test_helper"

class AppApiAgentHomesTest < ActionDispatch::IntegrationTest
  test "shows a virtual default workspace without creating a binding or workspace" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: runtime)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: runtime,
      display_name: "Alpha Agent"
    )
    create_agent_connection!(installation: installation, agent: agent)

    assert_no_difference(["UserAgentBinding.count", "Workspace.count"]) do
      get "/app_api/agents/#{agent.public_id}/home",
        headers: app_api_headers(session.plaintext_token)
    end

    assert_response :success

    response_body = response.parsed_body
    assert_equal "agent_home_show", response_body.fetch("method_id")
    assert_equal agent.public_id, response_body.fetch("agent").fetch("agent_id")
    default_workspace_ref = response_body.fetch("default_workspace_ref")
    assert_equal "virtual", default_workspace_ref.fetch("state")
    assert_equal agent.public_id, default_workspace_ref.fetch("agent_id")
    assert_equal user.public_id, default_workspace_ref.fetch("user_id")
    assert_equal "Default Workspace", default_workspace_ref.fetch("name")
    assert_equal "private", default_workspace_ref.fetch("privacy")
    assert_equal runtime.public_id, default_workspace_ref.fetch("default_execution_runtime_id")
    assert_equal [], response_body.fetch("workspaces")
    refute_includes response.body, %("#{agent.id}")
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

  test "shows agent home even when the agent default runtime is currently unavailable" do
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
    assert_equal "virtual", response.parsed_body.fetch("default_workspace_ref").fetch("state")
  end

  test "loads a materialized agent home within seven SQL queries" do
    context = create_workspace_context!
    context[:workspace].update!(is_default: true)
    create_workspace!(
      installation: context[:installation],
      user: context[:user],
      user_agent_binding: context[:user_agent_binding],
      default_execution_runtime: context[:execution_runtime],
      name: "Secondary Workspace"
    )
    session = create_session!(user: context[:user])

    assert_sql_query_count_at_most(7) do
      get "/app_api/agents/#{context[:agent].public_id}/home",
        headers: app_api_headers(session.plaintext_token)
    end

    assert_response :success
  end
end
