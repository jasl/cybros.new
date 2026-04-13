require "test_helper"

class TurnWorkflowBootstrapConstraintTest < ActiveSupport::TestCase
  test "defaults workflow bootstrap fields to not requested" do
    turn = create_turn_record!

    assert_equal "not_requested", turn.workflow_bootstrap_state
    assert_equal({}, turn.workflow_bootstrap_payload)
    assert_equal({}, turn.workflow_bootstrap_failure_payload)
    assert_nil turn.workflow_bootstrap_requested_at
    assert_nil turn.workflow_bootstrap_started_at
    assert_nil turn.workflow_bootstrap_finished_at
  end

  test "accepts the exact pending bootstrap payload shape" do
    turn = build_turn_record(
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
      workflow_bootstrap_requested_at: Time.current,
      workflow_bootstrap_started_at: nil,
      workflow_bootstrap_finished_at: nil
    )

    assert turn.valid?, turn.errors.full_messages.to_sentence
  end

  test "rejects pending bootstrap rows without the full payload contract" do
    turn = build_turn_record(
      workflow_bootstrap_state: "pending",
      workflow_bootstrap_payload: {
        "selector_source" => "app_api",
        "selector" => "candidate:codex_subscription/gpt-5.3-codex",
      },
      workflow_bootstrap_failure_payload: {},
      workflow_bootstrap_requested_at: Time.current
    )

    assert_not turn.valid?
    assert_includes turn.errors[:workflow_bootstrap_payload], "must match the workflow bootstrap contract"
  end

  test "rejects invalid workflow bootstrap state transitions" do
    turn = create_turn_record!

    turn.assign_attributes(
      workflow_bootstrap_state: "ready",
      workflow_bootstrap_payload: {
        "selector_source" => "app_api",
        "selector" => "candidate:codex_subscription/gpt-5.3-codex",
        "root_node_key" => "turn_step",
        "root_node_type" => "turn_step",
        "decision_source" => "system",
        "metadata" => {},
      },
      workflow_bootstrap_requested_at: Time.current,
      workflow_bootstrap_started_at: Time.current,
      workflow_bootstrap_finished_at: Time.current
    )

    assert_not turn.valid?
    assert_includes turn.errors[:workflow_bootstrap_state], "must follow the allowed workflow bootstrap transitions"
  end

  private

  def create_turn_record!(**attrs)
    build_turn_record(**attrs).tap(&:save!)
  end

  def build_turn_record(**attrs)
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    execution_epoch = initialize_current_execution_epoch!(conversation)

    Turn.new({
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
    }.merge(attrs))
  end
end
