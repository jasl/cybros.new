require "test_helper"

class AgentControl::ClosableResourceRegistryTest < ActiveSupport::TestCase
  test "fetches and finds supported closeable resources by public id" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment]
    )

    assert_equal ProcessRun, AgentControl::ClosableResourceRegistry.fetch("ProcessRun")
    assert AgentControl::ClosableResourceRegistry.supported?(process_run)
    assert_equal process_run, AgentControl::ClosableResourceRegistry.find!(
      installation_id: context[:installation].id,
      resource_type: "ProcessRun",
      public_id: process_run.public_id
    )
    assert_raises(KeyError) { AgentControl::ClosableResourceRegistry.fetch("Conversation") }
  end
end
