require "test_helper"

class EmbeddedAgents::ConversationObservation::BuildAssessmentTest < ActiveSupport::TestCase
  test "builds one canonical assessment per frame with stable proof refs" do
    freeze_time do
      fixture = build_observation_fixture!

      assessment = EmbeddedAgents::ConversationObservation::BuildAssessment.call(
        conversation_observation_frame: fixture.fetch(:frame),
        observation_bundle: fixture.fetch(:bundle)
      )

      assert_equal fixture.fetch(:session).public_id, assessment.fetch("observation_session_id")
      assert_equal fixture.fetch(:frame).public_id, assessment.fetch("observation_frame_id")
      assert_equal fixture.fetch(:conversation).public_id, assessment.fetch("conversation_id")
      assert_equal "waiting", assessment.fetch("overall_state")
      assert_equal "Waiting on subagent_barrier at implement", assessment.fetch("current_activity")
      assert_equal "subagent_barrier", assessment.fetch("blocking_reason")
      assert_equal fixture.fetch(:workflow_run).public_id, assessment.fetch("workflow_run_id")
      assert_equal fixture.fetch(:workflow_node).public_id, assessment.fetch("workflow_node_id")
      assert_equal 2, assessment.fetch("recent_activity_items").length
      assert_equal [fixture.fetch(:subagent_session).public_id], assessment.dig("proof_refs", "subagent_session_ids")
      assert_equal(
        [
          fixture.fetch(:first_turn).selected_input_message.public_id,
          fixture.fetch(:current_turn).selected_input_message.public_id,
          fixture.fetch(:current_turn).selected_output_message.public_id,
        ],
        assessment.fetch("transcript_refs")
      )
      assert_equal "The conversation is currently waiting. It is waiting for a running subagent before work on implement can continue. The latest tracked activity was a runtime.process_run.output event. This summary is grounded in workflow state, transcript context, recent activity, and subagent status.", assessment.fetch("human_summary")
      refute_match(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/, assessment.fetch("human_summary"))
      assert_includes assessment.fetch("proof_text"), fixture.fetch(:workflow_run).public_id
      assert_includes assessment.fetch("proof_text"), fixture.fetch(:workflow_node).public_id
      assert assessment.fetch("stall_for_ms") >= 0
      assert_equal Time.current.iso8601(6), assessment.fetch("observed_at")
    end
  end

  test "preserves the latest completed workflow run so terminal observation can report completion" do
    freeze_time do
      context = build_canonical_variable_context!
      workflow_node = create_workflow_node!(
        workflow_run: context.fetch(:workflow_run),
        node_key: "finalize",
        node_type: "turn_step",
        lifecycle_state: "completed",
        presentation_policy: "ops_trackable",
        decision_source: "agent_program",
        started_at: 5.minutes.ago,
        finished_at: 4.minutes.ago,
        metadata: {}
      )
      context.fetch(:workflow_run).update!(
        lifecycle_state: "completed",
        wait_state: "ready",
        wait_reason_payload: {}
      )
      session = ConversationObservationSession.create!(
        installation: context.fetch(:installation),
        target_conversation: context.fetch(:conversation),
        initiator: context.fetch(:user),
        lifecycle_state: "open",
        responder_strategy: "builtin",
        capability_policy_snapshot: {}
      )
      frame = EmbeddedAgents::ConversationObservation::BuildFrame.call(
        conversation_observation_session: session
      )
      bundle = EmbeddedAgents::ConversationObservation::BuildBundle.call(
        conversation_observation_frame: frame
      )

      assessment = EmbeddedAgents::ConversationObservation::BuildAssessment.call(
        conversation_observation_frame: frame,
        observation_bundle: bundle
      )

      assert_equal context.fetch(:workflow_run).public_id, frame.active_workflow_run_public_id
      assert_equal workflow_node.public_id, frame.active_workflow_node_public_id
      assert_equal "completed", assessment.fetch("overall_state")
      assert_equal context.fetch(:workflow_run).public_id, assessment.fetch("workflow_run_id")
    end
  end

  private

  def build_observation_fixture!
    context = build_bundle_context!
    session = ConversationObservationSession.create!(
      installation: context.fetch(:installation),
      target_conversation: context.fetch(:conversation),
      initiator: context.fetch(:user),
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {}
    )
    frame = EmbeddedAgents::ConversationObservation::BuildFrame.call(
      conversation_observation_session: session
    )
    bundle = EmbeddedAgents::ConversationObservation::BuildBundle.call(
      conversation_observation_frame: frame
    )

    context.merge(session: session, frame: frame, bundle: bundle)
  end

  def build_bundle_context!
    context = build_canonical_variable_context!
    conversation = context.fetch(:conversation)
    first_turn = context.fetch(:turn)
    first_output = attach_selected_output!(first_turn, content: "First answer")
    first_turn.update!(lifecycle_state: "completed")
    context.fetch(:workflow_run).update!(lifecycle_state: "completed")
    ConversationMessageVisibility.create!(
      installation: context.fetch(:installation),
      conversation: conversation,
      message: first_output,
      hidden: true,
      excluded_from_context: false
    )
    ProviderUsage::RecordEvent.call(
      installation: context.fetch(:installation),
      user: context.fetch(:user),
      workspace: context.fetch(:workspace),
      conversation_id: conversation.id,
      turn_id: first_turn.id,
      workflow_node_key: "turn_step",
      agent_program: context.fetch(:agent_program),
      agent_program_version: context.fetch(:agent_program_version),
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 120,
      output_tokens: 40,
      latency_ms: 900,
      estimated_cost: 0.012,
      success: true,
      occurred_at: 5.minutes.ago
    )

    current_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current progress update?",
      agent_program_version: context.fetch(:agent_program_version),
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(current_turn, content: "Working through the current implementation.")
    workflow_run = create_workflow_run!(turn: current_turn, wait_state: "ready", wait_reason_payload: {})
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "implement",
      node_type: "turn_step",
      lifecycle_state: "running",
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      started_at: 3.minutes.ago,
      metadata: {}
    )
    child_conversation = create_conversation_record!(
      installation: context.fetch(:installation),
      workspace: context.fetch(:workspace),
      parent_conversation: conversation,
      kind: "fork",
      execution_runtime: context.fetch(:execution_runtime),
      agent_program_version: context.fetch(:agent_program_version),
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context.fetch(:installation),
      owner_conversation: conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "subagent_barrier",
      wait_reason_payload: { "subagent_session_ids" => [subagent_session.public_id] },
      waiting_since_at: 2.minutes.ago
    )
    process_run = create_process_run!(
      workflow_node: workflow_node,
      execution_runtime: context.fetch(:execution_runtime),
      lifecycle_state: "running"
    )
    ConversationRuntime::PublishEvent.call(
      conversation: conversation,
      turn: current_turn,
      event_kind: "runtime.workflow_node.started",
      payload: {
        "workflow_run_id" => workflow_run.public_id,
        "workflow_node_id" => workflow_node.public_id,
        "state" => "running",
      }
    )
    ConversationRuntime::PublishEvent.call(
      conversation: conversation,
      turn: current_turn,
      event_kind: "runtime.process_run.output",
      payload: {
        "process_run_id" => process_run.public_id,
        "workflow_node_id" => workflow_node.public_id,
        "stream" => "stdout",
        "text" => "sensitive raw chunk",
      }
    )

    context.merge(
      conversation: conversation,
      first_turn: first_turn.reload,
      current_turn: current_turn.reload,
      workflow_run: workflow_run.reload,
      workflow_node: workflow_node.reload,
      subagent_session: subagent_session
    )
  end
end
