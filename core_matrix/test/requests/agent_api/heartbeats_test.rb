require "test_helper"

class AgentApiHeartbeatsTest < ActionDispatch::IntegrationTest
  test "connection credential authentication is required before a heartbeat can update agent connection health" do
    registration = register_agent_runtime!

    post "/agent_api/heartbeats",
      params: {
        health_status: "healthy",
        health_metadata: { latency_ms: 15 },
        auto_resume_eligible: true,
      },
      as: :json

    assert_response :unauthorized

    post "/agent_api/heartbeats",
      params: {
        health_status: "healthy",
        health_metadata: { latency_ms: 15 },
        auto_resume_eligible: true,
      },
      headers: agent_api_headers(registration[:agent_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "agent_health", response_body["method_id"]
    assert_equal registration[:agent_definition_version].public_id, response_body["agent_definition_version_id"]
    assert_equal registration[:agent_connection].public_id, response_body["agent_connection_id"]
    assert_equal "healthy", response_body["health_status"]
    assert_equal({ "latency_ms" => 15 }, response_body["health_metadata"])
    assert_equal true, response_body["auto_resume_eligible"]
    assert_equal "healthy", registration[:agent_connection].reload.health_status
    refute_includes response.body, %("#{registration[:agent_connection].id}")
  end
end
