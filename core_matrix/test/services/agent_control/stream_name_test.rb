require "test_helper"

class AgentControl::StreamNameTest < ActiveSupport::TestCase
  test "builds the action cable stream from the deployment public id" do
    context = build_agent_control_context!

    assert_equal "agent_control:deployment:#{context[:deployment].public_id}",
      AgentControl::StreamName.for_deployment(context[:deployment])
  end
end
