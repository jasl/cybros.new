require "test_helper"

class WorkflowRunTest < ActiveSupport::TestCase
  test "enforces one workflow per turn and one active workflow per conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_run = create_workflow_run!(turn: first_turn)
    duplicate_turn_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: first_turn,
      lifecycle_state: "completed"
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    competing_active_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: second_turn,
      lifecycle_state: "active"
    )

    assert first_run.active?
    assert_not duplicate_turn_run.valid?
    assert_includes duplicate_turn_run.errors[:turn_id], "has already been taken"
    assert_not competing_active_run.valid?
    assert_includes competing_active_run.errors[:conversation], "already has an active workflow"
  end

  test "tracks structured wait state fields" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Wait-state input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    waiting_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: turn,
      lifecycle_state: "active",
      wait_state: "waiting",
      wait_reason_kind: "policy_gate",
      wait_reason_payload: { "policy_mode" => "restart" },
      waiting_since_at: Time.current,
      blocking_resource_type: "Turn",
      blocking_resource_id: "queued-turn-1"
    )
    invalid_waiting_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: turn,
      lifecycle_state: "active",
      wait_state: "waiting",
      wait_reason_payload: {}
    )

    assert waiting_run.valid?
    assert_equal "restart", waiting_run.wait_reason_payload["policy_mode"]
    assert_not invalid_waiting_run.valid?
    assert_includes invalid_waiting_run.errors[:wait_reason_kind], "must exist when workflow run is waiting"
    assert_includes invalid_waiting_run.errors[:waiting_since_at], "must exist when workflow run is waiting"

    ready_with_stale_payload = create_workflow_run!(turn: turn, lifecycle_state: "completed").dup
    ready_with_stale_payload.assign_attributes(
      turn: Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Ready-state input",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      ),
      wait_state: "ready",
      wait_reason_payload: { "stale" => true }
    )

    assert_not ready_with_stale_payload.valid?
    assert_includes ready_with_stale_payload.errors[:wait_reason_payload], "must be empty when workflow run is ready"
  end
end
