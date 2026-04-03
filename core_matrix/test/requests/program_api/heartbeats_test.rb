require "test_helper"

class AgentApiHeartbeatsTest < ActionDispatch::IntegrationTest
  test "session credential authentication is required before a heartbeat can update agent session health" do
    registration = register_agent_runtime!

    post "/program_api/heartbeats",
      params: {
        health_status: "healthy",
        health_metadata: { latency_ms: 15 },
        auto_resume_eligible: true,
      },
      as: :json

    assert_response :unauthorized

    post "/program_api/heartbeats",
      params: {
        health_status: "healthy",
        health_metadata: { latency_ms: 15 },
        auto_resume_eligible: true,
      },
      headers: program_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal registration[:deployment].public_id, response_body["agent_program_version_id"]
    assert_equal registration[:agent_session].public_id, response_body["agent_session_id"]
    assert_equal "healthy", response_body["health_status"]
    assert_equal({ "latency_ms" => 15 }, response_body["health_metadata"])
    assert_equal true, response_body["auto_resume_eligible"]
    assert_equal "healthy", registration[:agent_session].reload.health_status
    refute_includes response.body, %("#{registration[:deployment].id}")
  end
end
