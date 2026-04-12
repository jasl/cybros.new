require "test_helper"

class AppApiAdminAgentsTest < ActionDispatch::IntegrationTest
  test "lists agents for the current installation using public ids" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: runtime)
    alpha = create_agent!(
      installation: installation,
      display_name: "Alpha Agent",
      default_execution_runtime: runtime
    )
    create_agent_connection!(installation: installation, agent: alpha)
    bravo = create_agent!(
      installation: installation,
      display_name: "Bravo Agent",
      visibility: "private",
      owner_user: admin,
      provisioning_origin: "user_created",
      key: "bravo-agent",
      default_execution_runtime: runtime
    )
    create_agent_connection!(installation: installation, agent: bravo)

    get "/app_api/admin/agents", headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "admin_agent_index", response_body.fetch("method_id")
    assert_equal [alpha.public_id, bravo.public_id], response_body.fetch("agents").map { |item| item.fetch("agent_id") }
    refute_includes response.body, %("#{alpha.id}")
  end
end
