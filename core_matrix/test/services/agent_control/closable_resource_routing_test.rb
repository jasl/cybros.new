require "test_helper"

class AgentControl::ClosableResourceRoutingTest < ActiveSupport::TestCase
  test "routes process and subagent resources back to their owning conversation context" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: context[:conversation],
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:deployment],
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      origin_turn: context[:turn],
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )

    assert_equal context[:execution_runtime], AgentControl::ClosableResourceRouting.execution_runtime_for(process_run)
    assert_equal context[:conversation], AgentControl::ClosableResourceRouting.conversation_for(process_run)
    assert_equal context[:turn], AgentControl::ClosableResourceRouting.turn_for(process_run)
    assert_equal context[:agent_program], AgentControl::ClosableResourceRouting.owning_agent_program_for(process_run)

    assert_equal context[:conversation], AgentControl::ClosableResourceRouting.conversation_for(subagent_session)
    assert_equal context[:turn], AgentControl::ClosableResourceRouting.turn_for(subagent_session)
    assert_equal context[:execution_runtime], AgentControl::ClosableResourceRouting.execution_runtime_for(subagent_session)
    assert_equal context[:agent_program], AgentControl::ClosableResourceRouting.owning_agent_program_for(subagent_session)
  end
end
