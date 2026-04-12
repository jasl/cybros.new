require "test_helper"

class WorkflowRunTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    ),
      content: "Workflow input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)

    assert workflow_run.public_id.present?
    assert_equal workflow_run, WorkflowRun.find_by_public_id!(workflow_run.public_id)
  end

  test "enforces one workflow per turn and one active workflow per conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_definition_version: context[:agent_definition_version],
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
      agent_definition_version: context[:agent_definition_version],
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
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Wait-state input",
      agent_definition_version: context[:agent_definition_version],
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
      wait_reason_payload: {},
      wait_policy_mode: "restart",
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
    assert_equal "restart", waiting_run.wait_policy_mode
    assert_not invalid_waiting_run.valid?
    assert_includes invalid_waiting_run.errors[:wait_reason_kind], "must exist when workflow run is waiting"
    assert_includes invalid_waiting_run.errors[:waiting_since_at], "must exist when workflow run is waiting"

    ready_with_stale_payload = create_workflow_run!(turn: turn, lifecycle_state: "completed").dup
    ready_with_stale_payload.assign_attributes(
      turn: Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Ready-state input",
        agent_definition_version: context[:agent_definition_version],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      ),
      wait_state: "ready",
      wait_reason_payload: { "stale" => true }
    )

    assert_not ready_with_stale_payload.valid?
    assert_includes ready_with_stale_payload.errors[:wait_reason_payload], "must be empty when workflow run is ready"
  end

  test "accepts external dependency blocked as a structured wait reason" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Blocked input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    workflow_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: turn,
      lifecycle_state: "active",
      wait_state: "waiting",
      wait_reason_kind: "external_dependency_blocked",
      wait_reason_payload: {},
      wait_failure_kind: "provider_credits_exhausted",
      wait_retry_scope: "step",
      wait_retry_strategy: "manual",
      wait_attempt_no: 1,
      waiting_since_at: Time.current,
      blocking_resource_type: "WorkflowNode",
      blocking_resource_id: "workflow-node-1"
    )

    assert workflow_run.valid?
  end

  test "requires deletion cancellation fields to be paired" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Deletion input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    workflow_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: turn,
      lifecycle_state: "active",
      cancellation_reason_kind: "conversation_deleted"
    )

    assert workflow_run.invalid?
    assert_includes workflow_run.errors[:cancellation_requested_at], "must exist when cancellation reason is present"
  end

  test "delegates resolved model references to the turn snapshot" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Selector input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {
        "normalized_selector" => "role:main",
        "resolved_provider_handle" => "codex_subscription",
        "resolved_model_ref" => "gpt-5.4",
      }
    )
    workflow_run = create_workflow_run!(turn: turn)

    assert_equal "role:main", workflow_run.normalized_selector
    assert_equal "codex_subscription", workflow_run.resolved_provider_handle
    assert_equal "gpt-5.4", workflow_run.resolved_model_ref
  end

  test "delegates execution snapshot fields through the explicit snapshot contract" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {
        "resolved_provider_handle" => "codex_subscription",
        "resolved_model_ref" => "gpt-5.4",
      }
    )
    Workflows::BuildExecutionSnapshot.call(turn: turn)
    workflow_run = create_workflow_run!(turn: turn)

    assert_equal turn.public_id, workflow_run.execution_identity.fetch("turn_id")
    assert_equal context[:agent_definition_version].public_id, workflow_run.execution_identity.fetch("agent_definition_version_id")
    assert_equal(
      [
        {
          "message_id" => turn.selected_input_message.public_id,
          "conversation_id" => conversation.public_id,
          "turn_id" => turn.public_id,
          "role" => "user",
          "slot" => "input",
          "content" => "Input",
        },
      ],
      workflow_run.execution_snapshot.conversation_projection.fetch("messages")
    )
  end

  test "derives workspace and feature policy from the turn instead of duplicate columns" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Derived workflow facts",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)

    refute_includes WorkflowRun.column_names, "workspace_id"
    refute_includes WorkflowRun.column_names, "feature_policy_snapshot"
    assert_equal conversation.workspace, workflow_run.workspace
    assert_equal turn.feature_policy_snapshot, workflow_run.feature_policy_snapshot
  end

  test "maps wait reasons into waiting and blocked supervision helpers" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )

    blocked_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Blocked workflow",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    blocked_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: blocked_turn,
      lifecycle_state: "active",
      wait_state: "waiting",
      wait_reason_kind: "external_dependency_blocked",
      wait_reason_payload: {},
      wait_failure_kind: "provider_credits_exhausted",
      wait_retry_scope: "step",
      wait_retry_strategy: "manual",
      wait_attempt_no: 1,
      waiting_since_at: Time.current
    )

    retry_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Retry workflow",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    retry_run = WorkflowRun.new(
      installation: conversation.installation,
      conversation: conversation,
      turn: retry_turn,
      lifecycle_state: "active",
      wait_state: "waiting",
      wait_reason_kind: "retryable_failure",
      wait_reason_payload: {},
      wait_failure_kind: "provider_error",
      wait_retry_scope: "step",
      wait_retry_strategy: "manual",
      wait_attempt_no: 1,
      waiting_since_at: Time.current
    )

    assert blocked_run.valid?
    assert blocked_run.waiting?
    assert blocked_run.blocked?

    assert retry_run.valid?
    assert retry_run.waiting?
    assert_not retry_run.blocked?
  end
end
