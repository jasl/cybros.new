require "test_helper"

class HumanInteractions::WithMutableRequestContextTest < ActiveSupport::TestCase
  test "yields the locked request workflow run and conversation" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )

    yielded_request = nil
    yielded_workflow_run = nil
    yielded_conversation = nil

    HumanInteractions::WithMutableRequestContext.call(request: request) do |locked_request, workflow_run, conversation|
      yielded_request = locked_request
      yielded_workflow_run = workflow_run
      yielded_conversation = conversation
    end

    assert_equal request.id, yielded_request.id
    assert_instance_of ApprovalRequest, yielded_request
    assert_equal context[:workflow_run].id, yielded_workflow_run.id
    assert_equal context[:conversation].id, yielded_conversation.id
  end

  test "rejects pending delete conversations on the request record" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Complete the task" }
    )
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::WithMutableRequestContext.call(request: request) { flunk "should not yield" }
    end

    assert_equal request.id, error.record.id
    assert_instance_of HumanTaskRequest, error.record
    assert_includes error.record.errors[:deletion_state], "must be retained before resolving human interaction"
  end

  test "rejects archived conversations on the request record" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanFormRequest",
      workflow_node: context[:workflow_node],
      blocking: false,
      request_payload: {
        "input_schema" => { "required" => ["ticket_id"] },
        "defaults" => {},
      }
    )
    context[:conversation].update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::WithMutableRequestContext.call(request: request) { flunk "should not yield" }
    end

    assert_equal request.id, error.record.id
    assert_instance_of HumanFormRequest, error.record
    assert_includes error.record.errors[:lifecycle_state], "must be active before resolving human interaction"
  end
end
