require "test_helper"

class HumanInteractions::ResolveApprovalTest < ActiveSupport::TestCase
  test "records approval outcome and resumes the same workflow run by default" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )

    resolved = HumanInteractions::ResolveApproval.call(
      approval_request: request,
      decision: "approved",
      result_payload: { "comment" => "Ship it." }
    )

    assert resolved.resolved?
    assert_equal "approved", resolved.resolution_kind
    assert_equal true, resolved.result_payload["approved"]
    assert_equal "Ship it.", resolved.result_payload["comment"]
    assert_equal context[:workflow_run].id, resolved.workflow_run_id
    assert resolved.workflow_run.reload.ready?

    live_projection = ConversationEvent.live_projection(conversation: context[:conversation])
    assert_equal 1, live_projection.size
    assert_equal "human_interaction.resolved", live_projection.first.event_kind
    assert_equal 1, live_projection.first.stream_revision

    assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::ResolveApproval.call(
        approval_request: resolved.reload,
        decision: "denied"
      )
    end
  end

  test "rejects late approval resolution for pending delete conversations" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::ResolveApproval.call(
        approval_request: request,
        decision: "approved"
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before resolving human interaction"
  end

  test "rejects approval resolution for archived conversations" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: false,
      request_payload: { "approval_scope" => "publish" }
    )
    context[:conversation].update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::ResolveApproval.call(
        approval_request: request,
        decision: "approved"
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before resolving human interaction"
  end

  test "rejects stale approval resolution after the request has already been resolved" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )
    stale_request = ApprovalRequest.find(request.id)

    HumanInteractions::ResolveApproval.call(
      approval_request: request,
      decision: "approved",
      result_payload: { "comment" => "Ship it." }
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::ResolveApproval.call(
        approval_request: stale_request,
        decision: "denied"
      )
    end

    assert_includes error.record.errors[:base], "must be open before approval resolution"
    assert_equal "approved", request.reload.resolution_kind
    assert_equal 1,
      ConversationEvent.where(
        conversation: context[:conversation],
        event_kind: "human_interaction.resolved",
        stream_key: "human_interaction_request:#{request.id}"
      ).count
  end
end
