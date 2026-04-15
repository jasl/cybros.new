require "test_helper"

class AppApiWorkspaceAgentsControllerTest < ActionDispatch::IntegrationTest
  test "creates a workspace agent mount with an explicit default execution runtime" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    runtime = create_execution_runtime!(installation: context[:installation], display_name: "Mounted Runtime")
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: runtime)
    agent = create_agent!(
      installation: context[:installation],
      visibility: "public",
      default_execution_runtime: runtime,
      display_name: "Mounted Agent"
    )

    assert_difference("WorkspaceAgent.count", +1) do
      post "/app_api/workspaces/#{context[:workspace].public_id}/workspace_agents",
        params: {
          agent_id: agent.public_id,
          default_execution_runtime_id: runtime.public_id,
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :created
    workspace_agent = WorkspaceAgent.order(:id).last
    assert_equal "workspace_agent_create", response.parsed_body.fetch("method_id")
    assert_equal context[:workspace].public_id, response.parsed_body.fetch("workspace_id")
    assert_equal workspace_agent.public_id, response.parsed_body.dig("workspace_agent", "workspace_agent_id")
    assert_equal agent.public_id, response.parsed_body.dig("workspace_agent", "agent_id")
    assert_equal runtime.public_id, response.parsed_body.dig("workspace_agent", "default_execution_runtime_id")
  end

  test "revokes a workspace agent mount without hiding the workspace" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])

    patch "/app_api/workspaces/#{context[:workspace].public_id}/workspace_agents/#{context[:workspace_agent].public_id}",
      params: {
        lifecycle_state: "revoked",
        revoked_reason_kind: "owner_revoked",
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :success
    assert_equal "workspace_agent_update", response.parsed_body.fetch("method_id")
    assert_equal "revoked", response.parsed_body.dig("workspace_agent", "lifecycle_state")
    assert_equal "owner_revoked", response.parsed_body.dig("workspace_agent", "revoked_reason_kind")

    get "/app_api/workspaces",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    workspace_payload = response.parsed_body.fetch("workspaces").find { |item| item.fetch("workspace_id") == context[:workspace].public_id }
    assert_equal context[:workspace_agent].public_id, workspace_payload.fetch("workspace_agents").first.fetch("workspace_agent_id")
    assert_equal "revoked", workspace_payload.fetch("workspace_agents").first.fetch("lifecycle_state")
  end

  test "rejects editing a mount after it has been revoked" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )
    runtime = create_execution_runtime!(installation: context[:installation], display_name: "Other Runtime")
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: runtime)

    patch "/app_api/workspaces/#{context[:workspace].public_id}/workspace_agents/#{context[:workspace_agent].public_id}",
      params: {
        default_execution_runtime_id: runtime.public_id,
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :unprocessable_entity
    assert_equal context[:execution_runtime], context[:workspace_agent].reload.default_execution_runtime
  end

  test "rejects changing mutable policy fields in the same request that revokes a mount" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    other_runtime = create_execution_runtime!(installation: context[:installation], display_name: "Other Runtime")
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: other_runtime)

    patch "/app_api/workspaces/#{context[:workspace].public_id}/workspace_agents/#{context[:workspace_agent].public_id}",
      params: {
        lifecycle_state: "revoked",
        revoked_reason_kind: "owner_revoked",
        default_execution_runtime_id: other_runtime.public_id,
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :unprocessable_entity
    assert_equal "active", context[:workspace_agent].reload.lifecycle_state
    assert_equal context[:execution_runtime], context[:workspace_agent].default_execution_runtime
    assert_nil context[:workspace_agent].revoked_at
    assert_nil context[:workspace_agent].revoked_reason_kind
  end

  test "rejects unsupported capability policy payload keys" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    agent = create_agent!(installation: context[:installation], visibility: "public")

    post "/app_api/workspaces/#{context[:workspace].public_id}/workspace_agents",
      params: {
        agent_id: agent.public_id,
        capability_policy_payload: {
          disabled_capabilities: ["control"],
          unexpected: true,
        },
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :unprocessable_entity
  end
end
