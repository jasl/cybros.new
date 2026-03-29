require "test_helper"

class Conversations::WorkBarrierQueryTest < ActiveSupport::TestCase
  test "projects work-barrier facts from the canonical blocker snapshot" do
    context = build_agent_control_context!
    conversation = context[:conversation]

    HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )

    snapshot = Conversations::BlockerSnapshotQuery.call(conversation: conversation)

    assert_equal snapshot.work_barrier.to_h, Conversations::WorkBarrierQuery.call(conversation: conversation).to_h
  end
end
