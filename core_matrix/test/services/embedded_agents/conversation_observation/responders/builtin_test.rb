require "test_helper"

module EmbeddedAgents
  module ConversationObservation
    module Responders
    end
  end
end

class EmbeddedAgents::ConversationObservation::Responders::BuiltinTest < ActiveSupport::TestCase
  test "derives supervisor and human projections from the same assessment and persists proof on the frame" do
    freeze_time do
      fixture = build_observation_fixture!

      first_response = EmbeddedAgents::ConversationObservation::RouteResponder.call(
        conversation_observation_session: fixture.fetch(:session),
        conversation_observation_frame: fixture.fetch(:frame),
        observation_bundle: fixture.fetch(:bundle),
        question: "What are you doing right now?"
      )
      second_response = EmbeddedAgents::ConversationObservation::RouteResponder.call(
        conversation_observation_session: fixture.fetch(:session),
        conversation_observation_frame: fixture.fetch(:frame),
        observation_bundle: fixture.fetch(:bundle),
        question: "What are you doing right now?"
      )

      assert_equal first_response, second_response
      assert_equal "builtin", first_response.fetch("responder_kind")

      assessment = first_response.fetch("assessment")
      supervisor_status = first_response.fetch("supervisor_status")
      human_sidechat = first_response.fetch("human_sidechat")

      assert_equal assessment.fetch("proof_refs"), supervisor_status.fetch("proof_refs")
      assert_equal assessment.fetch("proof_refs"), human_sidechat.fetch("proof_refs")
      assert_equal assessment.fetch("overall_state"), supervisor_status.fetch("overall_state")
      assert_equal assessment.fetch("current_activity"), human_sidechat.fetch("current_activity")
      refute_equal assessment.fetch("human_summary"), human_sidechat.fetch("content")
      refute_match(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/, human_sidechat.fetch("content"))
      assert_match(/\ARight now the conversation is /, human_sidechat.fetch("content"))
      assert_equal assessment, fixture.fetch(:frame).reload.assessment_payload
    end
  end

  test "changes the human sidechat projection based on the current question and prior observation history" do
    freeze_time do
      fixture = build_observation_fixture!
      previous_frame = fixture.fetch(:session).conversation_observation_frames.create!(
        installation: fixture.fetch(:session).installation,
        target_conversation: fixture.fetch(:session).target_conversation,
        anchor_turn_public_id: fixture.fetch(:frame).anchor_turn_public_id,
        anchor_turn_sequence_snapshot: fixture.fetch(:frame).anchor_turn_sequence_snapshot,
        conversation_event_projection_sequence_snapshot: fixture.fetch(:frame).conversation_event_projection_sequence_snapshot,
        active_workflow_run_public_id: fixture.fetch(:frame).active_workflow_run_public_id,
        active_workflow_node_public_id: fixture.fetch(:frame).active_workflow_node_public_id,
        wait_state: fixture.fetch(:frame).wait_state,
        wait_reason_kind: fixture.fetch(:frame).wait_reason_kind,
        active_subagent_session_public_ids: fixture.fetch(:frame).active_subagent_session_public_ids,
        runtime_state_snapshot: fixture.fetch(:frame).runtime_state_snapshot,
        bundle_snapshot: fixture.fetch(:frame).bundle_snapshot,
        assessment_payload: {}
      )
      fixture.fetch(:session).conversation_observation_messages.create!(
        installation: fixture.fetch(:session).installation,
        target_conversation: fixture.fetch(:session).target_conversation,
        conversation_observation_frame: previous_frame,
        role: "observer_agent",
        content: "Previous summary",
        metadata: {
          "supervisor_status" => {
            "overall_state" => "running",
            "current_activity" => "Running provider_round_1 (running)",
            "recent_activity_items" => [{ "projection_sequence" => 1, "event_kind" => "runtime.workflow_node.started" }],
            "transcript_refs" => [],
          },
        }
      )

      progress_response = EmbeddedAgents::ConversationObservation::RouteResponder.call(
        conversation_observation_session: fixture.fetch(:session),
        conversation_observation_frame: fixture.fetch(:frame),
        observation_bundle: fixture.fetch(:bundle),
        question: "What are you doing right now?"
      )
      change_response = EmbeddedAgents::ConversationObservation::RouteResponder.call(
        conversation_observation_session: fixture.fetch(:session),
        conversation_observation_frame: fixture.fetch(:frame),
        observation_bundle: fixture.fetch(:bundle),
        question: "What changed most recently?"
      )

      refute_equal progress_response.dig("human_sidechat", "content"), change_response.dig("human_sidechat", "content")
      assert_match(/Since the last observation/, change_response.dig("human_sidechat", "content"))
    end
  end

  test "transcript detail questions do not quote raw transcript content from the frozen observation snapshot" do
    freeze_time do
      fixture = build_observation_fixture!

      detail_response = EmbeddedAgents::ConversationObservation::RouteResponder.call(
        conversation_observation_session: fixture.fetch(:session),
        conversation_observation_frame: fixture.fetch(:frame),
        observation_bundle: fixture.fetch(:bundle),
        question: "What did it say earlier about the plan details?"
      )

      content = detail_response.dig("human_sidechat", "content")
      refute_includes content, "Working through the current implementation."
      refute_includes content, "Current progress update?"
      assert_match(/transcript ref|transcript surface|snapshot does not retain raw transcript text/i, content)
    end
  end

  private

  def build_observation_fixture!
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

    session = ConversationObservationSession.create!(
      installation: context.fetch(:installation),
      target_conversation: conversation,
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

    {
      session: session,
      frame: frame,
      bundle: bundle,
    }
  end
end
