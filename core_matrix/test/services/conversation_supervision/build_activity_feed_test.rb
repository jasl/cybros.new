require "test_helper"

class ConversationSupervision::BuildActivityFeedTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "returns the active turn feed when the conversation has active work" do
    context = build_agent_control_context!
    create_feed_entry!(context:, turn: context[:turn], sequence: 1, event_kind: "turn_todo_item_started", summary: "Started the board projection.")

    feed = ConversationSupervision::BuildActivityFeed.call(conversation: context[:conversation])

    assert_equal [context[:turn].public_id], feed.map { |entry| entry.fetch("turn_id") }.uniq
    assert_equal ["Started the board projection."], feed.map { |entry| entry.fetch("summary") }
  end

  test "returns the latest completed turn feed when no newer turn has started" do
    context = build_agent_control_context!
    context[:turn].update!(lifecycle_state: "completed")
    create_feed_entry!(context:, turn: context[:turn], sequence: 1, event_kind: "turn_completed", summary: "Finished the current turn.")

    feed = ConversationSupervision::BuildActivityFeed.call(conversation: context[:conversation])

    assert_equal [context[:turn].public_id], feed.map { |entry| entry.fetch("turn_id") }.uniq
    assert_equal ["turn_completed"], feed.map { |entry| entry.fetch("event_kind") }
  end

  test "keeps the supervision feed surface while using semantic fallback summaries for provider-backed work" do
    fixture = prepare_provider_backed_conversation_supervision_context!

    feed = ConversationSupervision::BuildActivityFeed.call(conversation: fixture.fetch(:conversation))

    assert feed.any? { |entry| entry.fetch("event_kind").start_with?("turn_todo_") }
    assert_includes feed.map { |entry| entry.fetch("summary") },
      "Started waiting for the test-and-build check in /workspace/game-2048."
    refute_match(/provider round|command_run_wait|exec_command/i, feed.to_json)
  end

  private

  def create_feed_entry!(context:, turn:, sequence:, event_kind:, summary:)
    ConversationSupervisionFeedEntry.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      target_turn: turn,
      sequence: sequence,
      event_kind: event_kind,
      summary: summary,
      details_payload: {},
      occurred_at: Time.current
    )
  end

  def create_feed_turn!(conversation:, template_turn:, sequence:, lifecycle_state:)
    Turn.create!(
      installation: template_turn.installation,
      conversation: conversation,
      agent_program_version: template_turn.agent_program_version,
      execution_runtime: template_turn.execution_runtime,
      sequence: sequence,
      lifecycle_state: lifecycle_state,
      origin_kind: "system_internal",
      origin_payload: {},
      pinned_program_version_fingerprint: template_turn.agent_program_version.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
  end
end
