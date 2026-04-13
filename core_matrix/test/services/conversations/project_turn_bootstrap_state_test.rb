require "test_helper"

class Conversations::ProjectTurnBootstrapStateTest < ActiveSupport::TestCase
  test "projects queued supervision state for a pending bootstrap turn" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    execution_epoch = initialize_current_execution_epoch!(conversation)
    turn = Turn.create!(
      installation: context[:installation],
      conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      agent_definition_version: context[:agent_definition_version],
      execution_epoch: execution_epoch,
      execution_runtime: execution_epoch.execution_runtime,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      agent_config_version: 1,
      agent_config_content_fingerprint: "cfg-#{next_test_sequence}",
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {},
      workflow_bootstrap_state: "pending",
      workflow_bootstrap_payload: {
        "selector_source" => "app_api",
        "selector" => "candidate:codex_subscription/gpt-5.3-codex",
        "root_node_key" => "turn_step",
        "root_node_type" => "turn_step",
        "decision_source" => "system",
        "metadata" => {},
      },
      workflow_bootstrap_failure_payload: {},
      workflow_bootstrap_requested_at: Time.current
    )
    message = UserMessage.create!(
      installation: context[:installation],
      conversation: conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Build a complete browser-playable React 2048 game and add automated tests."
    )
    Turns::PersistSelectionState.call(turn: turn, selected_input_message: message)

    state = Conversations::ProjectTurnBootstrapState.call(turn: turn)

    assert_equal "queued", state.overall_state
    assert_equal "queued", state.board_lane
    assert_equal "turn", state.current_owner_kind
    assert_equal turn.public_id, state.current_owner_public_id
    assert_equal "Build a complete browser-playable React 2048 game and add automated tests.", state.request_summary
    assert_equal turn.workflow_bootstrap_requested_at.to_i, state.last_progress_at.to_i
  end

  test "projects failed supervision state for a failed bootstrap turn" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    execution_epoch = initialize_current_execution_epoch!(conversation)
    turn = Turn.create!(
      installation: context[:installation],
      conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      agent_definition_version: context[:agent_definition_version],
      execution_epoch: execution_epoch,
      execution_runtime: execution_epoch.execution_runtime,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      agent_config_version: 1,
      agent_config_content_fingerprint: "cfg-#{next_test_sequence}",
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {},
      workflow_bootstrap_state: "pending",
      workflow_bootstrap_payload: {
        "selector_source" => "app_api",
        "selector" => "candidate:codex_subscription/gpt-5.3-codex",
        "root_node_key" => "turn_step",
        "root_node_type" => "turn_step",
        "decision_source" => "system",
        "metadata" => {},
      },
      workflow_bootstrap_failure_payload: {},
      workflow_bootstrap_requested_at: 2.minutes.ago
    )
    message = UserMessage.create!(
      installation: context[:installation],
      conversation: conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Build a complete browser-playable React 2048 game and add automated tests."
    )
    Turns::PersistSelectionState.call(turn: turn, selected_input_message: message)
    turn.update!(
      workflow_bootstrap_state: "materializing",
      workflow_bootstrap_started_at: 1.minute.ago
    )
    turn.update!(
      workflow_bootstrap_state: "failed",
      workflow_bootstrap_failure_payload: {
        "error_class" => "RuntimeError",
        "error_message" => "selector resolution blew up",
        "retryable" => true,
      },
      workflow_bootstrap_finished_at: Time.current
    )

    state = Conversations::ProjectTurnBootstrapState.call(turn: turn)

    assert_equal "failed", state.overall_state
    assert_equal "failed", state.board_lane
    assert_equal "turn", state.current_owner_kind
    assert_equal turn.public_id, state.current_owner_public_id
    assert_equal "Build a complete browser-playable React 2048 game and add automated tests.", state.request_summary
    assert_equal "selector resolution blew up", state.recent_progress_summary
    assert_equal turn.workflow_bootstrap_finished_at.to_i, state.last_progress_at.to_i
  end
end
