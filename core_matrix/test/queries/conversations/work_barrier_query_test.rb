require "test_helper"

class Conversations::WorkBarrierQueryTest < ActiveSupport::TestCase
  test "returns the blocker snapshot work-barrier projection" do
    context = build_agent_control_context!
    create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )

    barrier = Conversations::WorkBarrierQuery.call(conversation: context[:conversation])
    snapshot = Conversations::BlockerSnapshotQuery.call(conversation: context[:conversation])

    assert_equal snapshot.work_barrier.to_h, barrier.to_h
    assert_equal 1, barrier[:active_turn_count]
    assert_equal 1, barrier[:active_workflow_count]
    assert_equal 1, barrier[:running_turn_command_count]
  end
end
