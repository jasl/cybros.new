require "test_helper"

class ExecutionRuntimeApiCapabilitiesTest < ActionDispatch::IntegrationTest
  test "session refresh returns the current runtime version surface" do
    registration = register_agent_runtime!(
      execution_runtime_capability_payload: {
        "runtime_foundation" => {
          "docker_base_project" => "images/nexus",
        },
      },
      execution_runtime_tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "execution_runtime",
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "runtime/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ]
    )

    post "/execution_runtime_api/session/refresh",
      headers: execution_runtime_api_headers(registration[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "execution_runtime_session_refresh", response_body["method_id"]
    assert_equal registration[:execution_runtime].public_id, response_body["execution_runtime_id"]
    assert_equal registration[:execution_runtime].current_execution_runtime_version.public_id, response_body["execution_runtime_version_id"]
    assert_equal registration[:execution_runtime].execution_runtime_fingerprint, response_body["execution_runtime_fingerprint"]
    assert_equal registration[:execution_runtime].capability_payload, response_body["execution_runtime_capability_payload"]
  end

  test "session refresh accepts a version package update" do
    registration = register_agent_runtime!

    post "/execution_runtime_api/session/refresh",
      params: {
        version_package: {
          "execution_runtime_fingerprint" => registration[:execution_runtime].execution_runtime_fingerprint,
          "kind" => registration[:execution_runtime].kind,
          "protocol_version" => registration[:execution_runtime].current_execution_runtime_version.protocol_version,
          "sdk_version" => registration[:execution_runtime].current_execution_runtime_version.sdk_version,
          "capability_payload" => {
            "runtime_foundation" => {
              "docker_base_project" => "images/nexus",
            },
          },
          "tool_catalog" => registration[:execution_runtime].tool_catalog,
          "reflected_host_metadata" => registration[:execution_runtime].current_execution_runtime_version.reflected_host_metadata,
        },
      },
      headers: execution_runtime_api_headers(registration[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "execution_runtime_session_refresh", response_body["method_id"]
    assert_equal registration[:execution_runtime].public_id, response_body["execution_runtime_id"]
    assert_equal "images/nexus", response_body.dig("execution_runtime_capability_payload", "runtime_foundation", "docker_base_project")
  end

  test "legacy execution runtime capabilities routes are removed" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/execution_runtime_api/capabilities", method: :get)
    end

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/execution_runtime_api/capabilities", method: :post)
    end
  end
end
