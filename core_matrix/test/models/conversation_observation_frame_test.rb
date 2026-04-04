require "test_helper"

class ConversationObservationFrameTest < ActiveSupport::TestCase
  test "stores proof-facing public id anchors and assessment payload" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )
    session = ConversationObservationSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "mode" => "observe_only" }
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Observation anchor",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)

    frame = ConversationObservationFrame.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: session,
      anchor_turn_public_id: turn.public_id,
      anchor_turn_sequence_snapshot: turn.sequence,
      conversation_event_projection_sequence_snapshot: 12,
      active_workflow_run_public_id: workflow_run.public_id,
      active_workflow_node_public_id: workflow_run.public_id,
      wait_state: "waiting",
      wait_reason_kind: "external_dependency_blocked",
      active_subagent_session_public_ids: ["subagent-session-public"],
      runtime_state_snapshot: { "state" => "running" },
      bundle_snapshot: { "workflow_view" => { "workflow_run_id" => workflow_run.public_id } },
      assessment_payload: { "overall_state" => "running" }
    )

    assert frame.public_id.present?
    assert_equal frame, ConversationObservationFrame.find_by_public_id!(frame.public_id)
    assert_equal turn.public_id, frame.anchor_turn_public_id
    assert_equal workflow_run.public_id, frame.active_workflow_run_public_id
    assert_equal ["subagent-session-public"], frame.active_subagent_session_public_ids
    assert_equal({ "workflow_view" => { "workflow_run_id" => workflow_run.public_id } }, frame.bundle_snapshot)
    assert_equal({ "overall_state" => "running" }, frame.assessment_payload)
  end

  test "requires target conversation to match the session" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )
    other_installation = create_raw_installation!
    other_agent_program = create_agent_program!(installation: other_installation)
    other_user = create_user!(installation: other_installation)
    other_binding = create_user_program_binding!(
      installation: other_installation,
      user: other_user,
      agent_program: other_agent_program
    )
    other_workspace = create_workspace!(
      installation: other_installation,
      user: other_user,
      user_program_binding: other_binding
    )
    other_conversation = create_conversation_record!(
      workspace: other_workspace,
      installation: other_installation,
      execution_runtime: create_execution_runtime!(installation: other_installation),
      agent_program: other_agent_program
    )
    session = ConversationObservationSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {}
    )

    frame = ConversationObservationFrame.new(
      installation: context[:installation],
      target_conversation: other_conversation,
      conversation_observation_session: session,
      anchor_turn_public_id: "turn_public",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      wait_state: "ready",
      active_subagent_session_public_ids: [],
      runtime_state_snapshot: {},
      bundle_snapshot: {},
      assessment_payload: {}
    )

    assert_not frame.valid?
    assert_includes frame.errors[:target_conversation], "must match the observation session target conversation"
  end

  private

  def create_raw_installation!
    now = Time.current
    sql = <<~SQL.squish
      INSERT INTO installations (name, bootstrap_state, global_settings, created_at, updated_at)
      VALUES (#{ApplicationRecord.connection.quote("Observation Test Installation #{next_test_sequence}")},
              'bootstrapped',
              '{}',
              #{ApplicationRecord.connection.quote(now)},
              #{ApplicationRecord.connection.quote(now)})
      RETURNING id
    SQL
    installation_id = ApplicationRecord.connection.select_value(sql)
    Installation.find(installation_id)
  end
end
