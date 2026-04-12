require "test_helper"

class AppApiWorkspacesTest < ActionDispatch::IntegrationTest
  test "lists materialized workspaces for a visible agent using public ids only" do
    context = create_workspace_context!
    context[:workspace].update!(is_default: true)
    session = create_session!(user: context[:user])
    secondary_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      user_agent_binding: context[:user_agent_binding],
      default_execution_runtime: context[:execution_runtime],
      name: "Secondary Workspace"
    )

    get "/app_api/agents/#{context[:agent].public_id}/workspaces",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "agent_workspace_list", response_body.fetch("method_id")
    assert_equal context[:agent].public_id, response_body.fetch("agent_id")
    assert_equal [context[:workspace].public_id, secondary_workspace.public_id].sort,
      response_body.fetch("workspaces").map { |item| item.fetch("workspace_id") }.sort
    assert_equal context[:workspace].public_id, response_body.fetch("default_workspace_ref").fetch("workspace_id")
    assert_equal "materialized", response_body.fetch("default_workspace_ref").fetch("state")
    refute_includes response.body, %("#{context[:workspace].id}")
  end

  test "lists workspaces even when the agent default runtime is currently unavailable" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    context[:agent].default_execution_runtime.execution_runtime_connections.destroy_all

    get "/app_api/agents/#{context[:agent].public_id}/workspaces",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal "agent_workspace_list", response.parsed_body.fetch("method_id")
    assert_equal [context[:workspace].public_id], response.parsed_body.fetch("workspaces").map { |item| item.fetch("workspace_id") }
  end
end
