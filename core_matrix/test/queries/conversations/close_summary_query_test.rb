require "test_helper"

class Conversations::CloseSummaryQueryTest < ActiveSupport::TestCase
  test "projects the canonical blocker snapshot close summary" do
    context = build_agent_control_context!
    conversation = context[:conversation]

    HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )

    snapshot = Conversations::BlockerSnapshotQuery.call(conversation: conversation)

    assert_equal snapshot.close_summary, Conversations::CloseSummaryQuery.call(conversation: conversation)
  end
end
