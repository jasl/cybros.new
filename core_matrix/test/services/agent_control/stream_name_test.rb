require "test_helper"

class AgentControl::StreamNameTest < ActiveSupport::TestCase
  test "builds the action cable stream from the agent_definition_version public id" do
    context = build_agent_control_context!

    assert_equal "agent_control:agent_definition_version:#{context[:agent_definition_version].public_id}",
      AgentControl::StreamName.for_delivery_endpoint(context[:agent_definition_version])
  end
end
