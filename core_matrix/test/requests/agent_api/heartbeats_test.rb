require "test_helper"

class AgentApiHeartbeatsTest < ActionDispatch::IntegrationTest
  test "machine credential authentication is required before a heartbeat can update deployment health" do
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
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal registration[:deployment].public_id, response_body["deployment_id"]
    assert_equal "healthy", response_body["health_status"]
    assert_equal "active", response_body["bootstrap_state"]
    assert_equal "healthy", registration[:deployment].reload.health_status
    refute_includes response.body, %("#{registration[:deployment].id}")
  end
end
