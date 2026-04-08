require "test_helper"

class AgentApiHealthTest < ActionDispatch::IntegrationTest
  test "health endpoint returns session-backed runtime health" do
    registration = register_agent_runtime!
    AgentProgramVersions::RecordHeartbeat.call(
      agent_session: registration[:agent_session],
      health_status: "healthy",
      health_metadata: { "latency_ms" => 12 },
      auto_resume_eligible: true
    )

    get "/agent_api/health", headers: agent_api_headers(registration[:machine_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "agent_health", response_body["method_id"]
    assert_equal registration[:agent_program].public_id, response_body["agent_program_id"]
    assert_equal registration[:deployment].public_id, response_body["agent_program_version_id"]
    assert_equal registration[:agent_session].public_id, response_body["agent_session_id"]
    assert_equal registration[:executor_program].public_id, response_body["executor_program_id"]
    assert_equal registration[:executor_program].executor_fingerprint, response_body["executor_fingerprint"]
    assert_equal registration[:deployment].fingerprint, response_body["fingerprint"]
    assert_equal "healthy", response_body["health_status"]
    assert_equal({ "latency_ms" => 12 }, response_body["health_metadata"])
    assert_equal true, response_body["auto_resume_eligible"]
    assert_equal registration[:deployment].protocol_version, response_body["protocol_version"]
    assert_equal registration[:deployment].sdk_version, response_body["sdk_version"]
    assert_equal registration[:agent_session].reload.last_heartbeat_at.iso8601, response_body["last_heartbeat_at"]
    refute_includes response.body, %("#{registration[:deployment].id}")
  end
end
