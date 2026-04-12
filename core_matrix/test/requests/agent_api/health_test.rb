require "test_helper"

class AgentApiHealthTest < ActionDispatch::IntegrationTest
  test "health endpoint returns session-backed runtime health" do
    registration = register_agent_runtime!
    AgentConnections::RecordHeartbeat.call(
      agent_connection: registration[:agent_connection],
      health_status: "healthy",
      health_metadata: { "latency_ms" => 12 },
      auto_resume_eligible: true
    )

    get "/agent_api/health", headers: agent_api_headers(registration[:agent_connection_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "agent_health", response_body["method_id"]
    assert_equal registration[:agent].public_id, response_body["agent_id"]
    assert_equal registration[:agent_definition_version].public_id, response_body["agent_definition_version_id"]
    assert_equal registration[:agent_connection].public_id, response_body["agent_connection_id"]
    assert_equal registration[:execution_runtime].public_id, response_body["execution_runtime_id"]
    assert_equal registration[:execution_runtime].current_execution_runtime_version.public_id, response_body["execution_runtime_version_id"]
    assert_equal registration[:execution_runtime].execution_runtime_fingerprint, response_body["execution_runtime_fingerprint"]
    assert_equal registration[:agent_definition_version].definition_fingerprint, response_body["agent_definition_fingerprint"]
    assert_equal "healthy", response_body["health_status"]
    assert_equal({ "latency_ms" => 12 }, response_body["health_metadata"])
    assert_equal true, response_body["auto_resume_eligible"]
    assert_equal registration[:agent_definition_version].protocol_version, response_body["protocol_version"]
    assert_equal registration[:agent_definition_version].sdk_version, response_body["sdk_version"]
    assert_equal registration[:agent_connection].reload.last_heartbeat_at.iso8601, response_body["last_heartbeat_at"]
    refute_includes response.body, %("#{registration[:agent_definition_version].id}")
  end
end
