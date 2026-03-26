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
    assert_equal request.public_id, workflow_run.blocking_resource_id
    assert_equal request.public_id, workflow_run.wait_reason_payload["request_id"]

    event = ConversationEvent.find_by!(source: request, event_kind: "human_interaction.opened")
    assert_equal 0, event.projection_sequence
    assert_equal "human_interaction_request:#{request.id}", event.stream_key
    assert_equal 0, event.stream_revision
    assert_equal request.public_id, event.payload["request_id"]
  end

  test "rejects opening a human interaction on a pending delete conversation" do
    context = build_human_interaction_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "ApprovalRequest",
        workflow_node: context[:workflow_node],
        blocking: true,
        request_payload: { "approval_scope" => "publish" }
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before opening human interaction"
  end

  test "rejects opening a human interaction on an archived conversation" do
    context = build_human_interaction_context!
    context[:conversation].update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "ApprovalRequest",
        workflow_node: context[:workflow_node],
        blocking: true,
        request_payload: { "approval_scope" => "publish" }
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before opening human interaction"
  end

  test "rejects opening another blocking human interaction from a stale workflow snapshot" do
    context = build_human_interaction_context!
    stale_workflow_node = WorkflowNode.find(context[:workflow_node].id)
    stale_workflow_node.workflow_run

    first_request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "ApprovalRequest",
        workflow_node: stale_workflow_node,
        blocking: true,
        request_payload: { "approval_scope" => "publish-again" }
      )
    end

    assert_includes error.record.errors[:wait_state], "must be ready before opening another blocking human interaction"
    assert_equal [first_request.id], HumanInteractionRequest.where(workflow_run: context[:workflow_run]).order(:id).pluck(:id)
  end

  test "rejects opening a human interaction after the turn has been interrupted" do
    context = build_human_interaction_context!
    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "ApprovalRequest",
        workflow_node: context[:workflow_node],
        blocking: true,
        request_payload: { "approval_scope" => "publish" }
      )
    end

    assert_includes error.record.errors[:turn], "must not be fenced by turn interrupt"
  end
end
