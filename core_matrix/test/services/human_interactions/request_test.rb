require "test_helper"

class HumanInteractions::RequestTest < ActiveSupport::TestCase
  test "creates blocking approval requests, waits the workflow, and projects a conversation event" do
    context = build_human_interaction_context!

    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" },
      expires_at: 1.hour.from_now
    )

    assert_instance_of ApprovalRequest, request
    assert request.open?
    assert_equal context[:workflow_run], request.workflow_run

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "human_interaction", workflow_run.wait_reason_kind
    assert_equal "HumanInteractionRequest", workflow_run.blocking_resource_type
    assert_equal request.id.to_s, workflow_run.blocking_resource_id

    event = ConversationEvent.find_by!(source: request, event_kind: "human_interaction.opened")
    assert_equal 0, event.projection_sequence
    assert_equal "human_interaction_request:#{request.id}", event.stream_key
    assert_equal 0, event.stream_revision
  end
end
