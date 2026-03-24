require "test_helper"

class AgentApiHealthTest < ActionDispatch::IntegrationTest
  test "health endpoint returns machine-facing deployment health shape" do
    registration = register_agent_runtime!
    AgentDeployments::RecordHeartbeat.call(
      deployment: registration[:deployment],
      health_status: "healthy",
      health_metadata: { "latency_ms" => 12 },
      auto_resume_eligible: true
    )

    get "/agent_api/health", headers: agent_api_headers(registration[:machine_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "agent_health", response_body["method_id"]
    assert_equal registration[:deployment].fingerprint, response_body["fingerprint"]
    assert_equal "healthy", response_body["health_status"]
    assert_equal registration[:capability_snapshot].version, response_body["agent_capabilities_version"]
  end
end
