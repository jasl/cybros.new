require "test_helper"

class EmbeddedAgents::ConversationObservation::BuildBundleTest < ActiveSupport::TestCase
  test "builds a bounded observation bundle from transcript workflow activity and diagnostics" do
    context = build_bundle_context!
    session = create_observation_session!(context:)
    frame = EmbeddedAgents::ConversationObservation::BuildFrame.call(
      conversation_observation_session: session
    )

    bundle = EmbeddedAgents::ConversationObservation::BuildBundle.call(
      conversation_observation_frame: frame
    )

    assert_equal %w[activity_view subagent_view transcript_view workflow_view], bundle.keys.sort

    transcript_ids = bundle.fetch("transcript_view").fetch("messages").map { |message| message.fetch("message_id") }
    assert_equal(
      [
        context.fetch(:first_turn).selected_input_message.public_id,
        context.fetch(:current_turn).selected_input_message.public_id,
        context.fetch(:current_turn).selected_output_message.public_id,
      ],
      transcript_ids
    )
    refute_includes transcript_ids, context.fetch(:hidden_output).public_id

    workflow_view = bundle.fetch("workflow_view")
    assert_equal context.fetch(:workflow_run).public_id, workflow_view.fetch("workflow_run_id")
    assert_equal context.fetch(:workflow_node).public_id, workflow_view.fetch("workflow_node_id")
    assert_equal "waiting", workflow_view.fetch("wait_state")
    assert_equal "subagent_barrier", workflow_view.fetch("wait_reason_kind")
    refute workflow_view.key?("conversation_id")
    refute workflow_view.key?("wait_reason_payload")
    refute workflow_view.key?("resume_policy")

    transcript_messages = bundle.fetch("transcript_view").fetch("messages")
    refute_empty transcript_messages
    assert transcript_messages.all? { |message| message.keys.sort == %w[created_at message_id role slot] }
    refute transcript_messages.any? { |message| message.key?("content") }
    refute transcript_messages.any? { |message| message.key?("turn_id") }

    activity_items = bundle.fetch("activity_view").fetch("items")
    assert_equal ["runtime.workflow_node.started", "runtime.process_run.output"], activity_items.map { |item| item.fetch("event_kind") }
    refute activity_items.any? { |item| item.fetch("event_kind") == "message.appended" }
    assert activity_items.all? { |item| item.keys.sort == %w[created_at event_kind projection_sequence] }
    refute activity_items.any? { |item| item.key?("payload") }
    refute activity_items.any? { |item| item.key?("stream_key") }
    refute activity_items.any? { |item| item.key?("stream_revision") }
    refute activity_items.any? { |item| item.key?("turn_id") }

    subagent_view = bundle.fetch("subagent_view")
    assert_equal [context.fetch(:subagent_session).public_id], subagent_view.fetch("items").map { |item| item.fetch("subagent_session_id") }
    assert_equal "running", subagent_view.fetch("items").first.fetch("observed_status")
    assert_equal %w[observed_status profile_key subagent_session_id], subagent_view.fetch("items").first.keys.sort
    assert_public_id_boundaries!(bundle)
  end

  test "returns the frozen bundle snapshot even after the target conversation advances" do
    context = build_bundle_context!
    session = create_observation_session!(context:)
    frame = EmbeddedAgents::ConversationObservation::BuildFrame.call(
      conversation_observation_session: session
    )
    frozen_bundle = EmbeddedAgents::ConversationObservation::BuildBundle.call(
      conversation_observation_frame: frame
    )

    later_turn = Turns::StartUserTurn.call(
      conversation: context.fetch(:conversation),
      content: "A later turn that should not appear in the frozen bundle",
      agent_program_version: context.fetch(:agent_program_version),
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    later_output = attach_selected_output!(later_turn, content: "A later output that should stay out of the frozen bundle")
    ConversationRuntime::PublishEvent.call(
      conversation: context.fetch(:conversation),
      turn: later_turn,
      event_kind: "runtime.workflow_node.completed",
      payload: {
        "workflow_run_id" => context.fetch(:workflow_run).public_id,
        "workflow_node_id" => context.fetch(:workflow_node).public_id,
        "state" => "completed",
      }
    )

    reloaded_bundle = EmbeddedAgents::ConversationObservation::BuildBundle.call(
      conversation_observation_frame: frame.reload
    )

    assert_equal frozen_bundle, reloaded_bundle

    transcript_ids = reloaded_bundle.fetch("transcript_view").fetch("messages").map { |message| message.fetch("message_id") }
    refute_includes transcript_ids, later_turn.selected_input_message.public_id
    refute_includes transcript_ids, later_output.public_id
    refute reloaded_bundle.fetch("activity_view").fetch("items").any? { |item| item.fetch("event_kind") == "runtime.workflow_node.completed" }
  end

  private

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
      occurred_at: Time.utc(2026, 4, 4, 10, 0, 0)
    )

    current_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current progress update?",
      agent_program_version: context.fetch(:agent_program_version),
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    current_output = attach_selected_output!(current_turn, content: "Working through the current implementation.")
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
    ConversationEvents::Project.call(
      conversation: conversation,
      turn: current_turn,
      event_kind: "message.appended",
      payload: { "message_id" => current_output.public_id }
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
      first_turn: first_turn.reload,
      hidden_output: first_output,
      current_turn: current_turn.reload,
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

  def assert_public_id_boundaries!(value, key_path = [])
    case value
    when Hash
      value.each do |key, nested|
        if key.to_s.end_with?("_id")
          assert_kind_of String, nested, "expected #{(key_path + [key]).join(".")} to use a public id string"
        elsif key.to_s.end_with?("_ids")
          assert_kind_of Array, nested, "expected #{(key_path + [key]).join(".")} to use an array of public id strings"
          assert nested.all? { |item| item.is_a?(String) }, "expected #{(key_path + [key]).join(".")} to contain only public id strings"
        end

        assert_public_id_boundaries!(nested, key_path + [key])
      end
    when Array
      value.each_with_index do |nested, index|
        assert_public_id_boundaries!(nested, key_path + [index])
      end
    end
  end
end
