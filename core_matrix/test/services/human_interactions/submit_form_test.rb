require "test_helper"

class HumanInteractions::SubmitFormTest < ActiveSupport::TestCase
  test "validates required fields before submission" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanFormRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: {
        "input_schema" => { "required" => ["ticket_id"] },
        "defaults" => { "priority" => "high" },
      }
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::SubmitForm.call(
        human_form_request: request,
        submission_payload: { "priority" => "low" }
      )
    end

    assert_includes error.record.errors[:result_payload], "must include required field ticket_id"
  end

  test "times out expired blocking forms and resumes the same workflow run" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanFormRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: {
        "input_schema" => { "required" => ["ticket_id"] },
        "defaults" => {},
      },
      expires_at: 1.minute.ago
    )

    timed_out = HumanInteractions::SubmitForm.call(
      human_form_request: request,
      submission_payload: { "ticket_id" => "T-1000" }
    )

    assert timed_out.timed_out?
    assert_equal "timed_out", timed_out.resolution_kind
    assert timed_out.workflow_run.reload.ready?

    live_projection = ConversationEvent.live_projection(conversation: context[:conversation])
    assert_equal "human_interaction.timed_out", live_projection.first.event_kind
  end

  test "rejects late form submission for pending delete conversations" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanFormRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: {
        "input_schema" => { "required" => ["ticket_id"] },
        "defaults" => {},
      }
    )
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::SubmitForm.call(
        human_form_request: request,
        submission_payload: { "ticket_id" => "T-1000" }
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before resolving human interaction"
  end

  test "rejects form submission for archived conversations" do
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
      HumanInteractions::SubmitForm.call(
        human_form_request: request,
        submission_payload: { "ticket_id" => "T-1000" }
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before resolving human interaction"
  end

  test "rejects form submission while close is in progress" do
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
    ConversationCloseOperation.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::SubmitForm.call(
        human_form_request: request,
        submission_payload: { "ticket_id" => "T-1000" }
      )
    end

    assert_includes error.record.errors[:base], "must not resolve human interaction while close is in progress"
  end

  test "rejects stale form submission after the request has already been resolved" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanFormRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: {
        "input_schema" => { "required" => ["ticket_id"] },
        "defaults" => {},
      }
    )
    stale_request = HumanFormRequest.find(request.id)

    HumanInteractions::SubmitForm.call(
      human_form_request: request,
      submission_payload: { "ticket_id" => "T-1000" }
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::SubmitForm.call(
        human_form_request: stale_request,
        submission_payload: { "ticket_id" => "T-2000" }
      )
    end

    assert_includes error.record.errors[:base], "must be open before form submission"
    assert_equal "T-1000", request.reload.result_payload["ticket_id"]
    assert_equal 1,
      ConversationEvent.where(
        conversation: context[:conversation],
        event_kind: "human_interaction.resolved",
        stream_key: "human_interaction_request:#{request.id}"
      ).count
  end
end
