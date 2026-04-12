require "test_helper"

class AppApiAdminExecutionRuntimesTest < ActionDispatch::IntegrationTest
  test "lists execution runtimes for the current installation using public ids" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    session = create_session!(user: admin)
    alpha = create_execution_runtime!(installation: installation, display_name: "Alpha Runtime")
    create_execution_runtime_connection!(installation: installation, execution_runtime: alpha)
    bravo = create_execution_runtime!(
      installation: installation,
      display_name: "Bravo Runtime",
      visibility: "private",
      owner_user: admin,
      provisioning_origin: "user_created"
    )
    create_execution_runtime_connection!(installation: installation, execution_runtime: bravo)

    get "/app_api/admin/execution_runtimes", headers: app_api_headers(session.plaintext_token)

    assert_response :success

    response_body = response.parsed_body
    assert_equal "admin_execution_runtime_index", response_body.fetch("method_id")
    assert_equal [alpha.public_id, bravo.public_id], response_body.fetch("execution_runtimes").map { |item| item.fetch("execution_runtime_id") }
    refute_includes response.body, %("#{alpha.id}")
  end
end
