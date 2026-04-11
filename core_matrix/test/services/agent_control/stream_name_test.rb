require "test_helper"

class AgentControl::StreamNameTest < ActiveSupport::TestCase
  test "builds the action cable stream from the agent_snapshot public id" do
    context = build_agent_control_context!

    assert_equal "agent_control:agent_snapshot:#{context[:agent_snapshot].public_id}",
      AgentControl::StreamName.for_delivery_endpoint(context[:agent_snapshot])
  end
end
