require "test_helper"

class HumanInteractionRequestTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = build_human_interaction_context!
    request = ApprovalRequest.create!(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      conversation: context[:conversation],
      turn: context[:turn],
      lifecycle_state: "open",
      blocking: true,
      request_payload: { "approval_scope" => "publish" },
      result_payload: {}
    )

    assert request.public_id.present?
    assert_equal request, HumanInteractionRequest.find_by_public_id!(request.public_id)
  end

  test "requires a supported sti subtype and keeps workflow ownership aligned" do
    context = build_human_interaction_context!

    request = ApprovalRequest.new(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      conversation: context[:conversation],
      turn: context[:turn],
      lifecycle_state: "open",
      blocking: true,
      request_payload: { "approval_scope" => "publish" },
      result_payload: {}
    )

    assert request.valid?

    base_request = HumanInteractionRequest.new(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      conversation: context[:conversation],
      turn: context[:turn],
      lifecycle_state: "open",
      blocking: true,
      request_payload: {},
      result_payload: {}
    )

    assert_not base_request.valid?
    assert_includes base_request.errors[:type], "must be a supported human interaction request subtype"

    mismatched_turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Different turn",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    request.turn = mismatched_turn

    assert_not request.valid?
    assert_includes request.errors[:turn], "must match the workflow run turn"
  end
end
