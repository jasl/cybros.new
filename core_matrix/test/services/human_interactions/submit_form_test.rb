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
end
