require "test_helper"

class EmbeddedAgents::ConversationObservation::BuildFrameTest < ActiveSupport::TestCase
  test "freezes a lightweight observation anchor from current conversation state" do
    context = build_observation_context!
    session = create_observation_session!(context:)

    frame = EmbeddedAgents::ConversationObservation::BuildFrame.call(
      conversation_observation_session: session
    )

    assert_instance_of ConversationObservationFrame, frame
    assert_equal session, frame.conversation_observation_session
    assert_equal context.fetch(:conversation), frame.target_conversation
    assert_equal context.fetch(:turn).public_id, frame.anchor_turn_public_id
    assert_equal context.fetch(:turn).sequence, frame.anchor_turn_sequence_snapshot
    assert_equal context.fetch(:workflow_run).public_id, frame.active_workflow_run_public_id
    assert_equal context.fetch(:workflow_node).public_id, frame.active_workflow_node_public_id
    assert_equal "waiting", frame.wait_state
    assert_equal "subagent_barrier", frame.wait_reason_kind
    assert_equal [context.fetch(:subagent_session).public_id], frame.active_subagent_session_public_ids
    assert_equal %w[activity_view subagent_view transcript_view workflow_view], frame.bundle_snapshot.keys.sort
    assert_equal context.fetch(:workflow_run).public_id, frame.bundle_snapshot.dig("workflow_view", "workflow_run_id")
    assert_equal({}, frame.assessment_payload)
    assert frame.conversation_event_projection_sequence_snapshot >= 0
  end

  private

  def build_observation_context!
    context = build_canonical_variable_context!
    workflow_run = context.fetch(:workflow_run)
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "turn_step",
      node_type: "turn_step",
      lifecycle_state: "running",
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      started_at: 2.minutes.ago,
      metadata: {}
    )
    child_conversation = create_conversation_record!(
      installation: context.fetch(:installation),
      workspace: context.fetch(:workspace),
      parent_conversation: context.fetch(:conversation),
      kind: "fork",
      execution_runtime: context.fetch(:execution_runtime),
      agent_program_version: context.fetch(:agent_program_version),
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context.fetch(:installation),
      owner_conversation: context.fetch(:conversation),
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "subagent_barrier",
      wait_reason_payload: {},
      waiting_since_at: 1.minute.ago
    )
    ConversationRuntime::PublishEvent.call(
      conversation: context.fetch(:conversation),
      turn: context.fetch(:turn),
      event_kind: "runtime.workflow_node.started",
      payload: {
        "workflow_run_id" => workflow_run.public_id,
        "workflow_node_id" => workflow_node.public_id,
        "state" => "running",
      }
    )

    context.merge(
      workflow_run: workflow_run.reload,
      workflow_node: workflow_node.reload,
      subagent_session: subagent_session
    )
  end

  def create_observation_session!(context:)
    ConversationObservationSession.create!(
      installation: context.fetch(:installation),
      target_conversation: context.fetch(:conversation),
      initiator: context.fetch(:user),
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {}
    )
  end
end
