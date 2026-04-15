require "test_helper"

class AppApiWorkspacesTest < ActionDispatch::IntegrationTest
  test "lists owned workspaces with nested workspace agents using public ids only" do
    context = create_workspace_context!
    context[:workspace].update!(is_default: true)
    session = create_session!(user: context[:user])
    secondary_agent = create_agent!(
      installation: context[:installation],
      default_execution_runtime: context[:execution_runtime]
    )
    secondary_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      name: "Secondary Workspace"
    )
    secondary_workspace_agent = create_workspace_agent!(
      installation: context[:installation],
      workspace: secondary_workspace,
      agent: secondary_agent,
      default_execution_runtime: context[:execution_runtime]
    )

    get "/app_api/workspaces",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "workspace_list", response_body.fetch("method_id")
    assert_equal [context[:workspace].public_id, secondary_workspace.public_id].sort,
      response_body.fetch("workspaces").map { |item| item.fetch("workspace_id") }.sort

    primary_payload = response_body.fetch("workspaces").find { |item| item.fetch("workspace_id") == context[:workspace].public_id }
    assert_equal true, primary_payload.fetch("is_default")
    assert_equal context[:workspace_agent].public_id, primary_payload.fetch("workspace_agents").first.fetch("workspace_agent_id")
    assert_equal context[:agent].public_id, primary_payload.fetch("workspace_agents").first.fetch("agent_id")
    assert_equal context[:execution_runtime].public_id, primary_payload.fetch("workspace_agents").first.fetch("default_execution_runtime_id")

    secondary_payload = response_body.fetch("workspaces").find { |item| item.fetch("workspace_id") == secondary_workspace.public_id }
    assert_equal secondary_workspace_agent.public_id, secondary_payload.fetch("workspace_agents").first.fetch("workspace_agent_id")
    refute_includes response.body, %("#{context[:workspace].id}")
  end

  test "keeps a workspace visible even when its mounted agent is revoked" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "agent_visibility_revoked"
    )

    get "/app_api/workspaces",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    workspace_payload = response.parsed_body.fetch("workspaces").find { |item| item.fetch("workspace_id") == context[:workspace].public_id }
    assert_equal "revoked", workspace_payload.fetch("workspace_agents").first.fetch("lifecycle_state")
    assert_equal "agent_visibility_revoked", workspace_payload.fetch("workspace_agents").first.fetch("revoked_reason_kind")
  end

  test "lists owned workspaces within seven SQL queries" do
    context = create_workspace_context!
    context[:workspace].update!(is_default: true)
    workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      name: "Secondary Workspace"
    )
    create_workspace_agent!(
      installation: context[:installation],
      workspace: workspace,
      agent: context[:agent],
      default_execution_runtime: context[:execution_runtime]
    )
    session = create_session!(user: context[:user])

    assert_sql_query_count_at_most(7) do
      get "/app_api/workspaces",
        headers: app_api_headers(session.plaintext_token)
    end

    assert_response :success
  end
end
