require "test_helper"

class AppApiAgentsTest < ActionDispatch::IntegrationTest
  test "lists only active agents visible to the signed-in user" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: runtime)
    public_agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: runtime,
      display_name: "Alpha Agent"
    )
    create_agent_connection!(installation: installation, agent: public_agent)
    owned_private_agent = create_agent!(
      installation: installation,
      visibility: "private",
      owner_user: user,
      provisioning_origin: "user_created",
      key: "owned-private-agent",
      default_execution_runtime: runtime,
      display_name: "Bravo Agent"
    )
    create_agent_connection!(installation: installation, agent: owned_private_agent)
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other Owner"
    )
    create_agent!(
      installation: installation,
      visibility: "private",
      owner_user: other_user,
      provisioning_origin: "user_created",
      key: "hidden-private-agent",
      display_name: "Hidden Agent"
    )
    create_agent!(
      installation: installation,
      visibility: "public",
      lifecycle_state: "retired",
      key: "retired-agent",
      display_name: "Retired Agent"
    )
    create_agent!(
      installation: installation,
      visibility: "public",
      key: "unconfigured-agent",
      display_name: "Unconfigured Agent"
    )

    get "/app_api/agents", headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "agents_index", response_body.fetch("method_id")
    assert_equal [public_agent.public_id, owned_private_agent.public_id], response_body.fetch("agents").map { |item| item.fetch("agent_id") }
    refute_includes response.body, %("#{public_agent.id}")
  end
end
