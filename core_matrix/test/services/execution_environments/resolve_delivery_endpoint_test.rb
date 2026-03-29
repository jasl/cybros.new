require "test_helper"

class ExecutionEnvironments::ResolveDeliveryEndpointTest < ActiveSupport::TestCase
  test "prefers the most recently active deployment before pending fallbacks" do
    context = build_agent_control_context!
    other_agent_installation = create_agent_installation!(installation: context[:installation])
    older_active = create_agent_deployment!(
      installation: context[:installation],
      agent_installation: other_agent_installation,
      execution_environment: context[:execution_environment],
      bootstrap_state: "active",
      health_status: "healthy",
      last_control_activity_at: 10.minutes.ago,
      last_heartbeat_at: 10.minutes.ago
    )
    context[:deployment].update!(
      last_control_activity_at: 1.minute.ago,
      last_heartbeat_at: 1.minute.ago
    )
    pending_installation = create_agent_installation!(installation: context[:installation])
    pending_deployment = create_agent_deployment!(
      installation: context[:installation],
      agent_installation: pending_installation,
      execution_environment: context[:execution_environment],
      bootstrap_state: "pending",
      last_heartbeat_at: Time.current
    )

    assert_equal context[:deployment], ExecutionEnvironments::ResolveDeliveryEndpoint.call(
      execution_environment: context[:execution_environment]
    )

    older_active.update!(bootstrap_state: "superseded")
    context[:deployment].update!(bootstrap_state: "superseded")

    assert_equal pending_deployment, ExecutionEnvironments::ResolveDeliveryEndpoint.call(
      execution_environment: context[:execution_environment]
    )
  end
end
