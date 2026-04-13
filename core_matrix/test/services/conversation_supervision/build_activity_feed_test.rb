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

  test "loads the anchored turn feed without an extra turn lookup" do
    context = build_agent_control_context!
    create_feed_entry!(context:, turn: context[:turn], sequence: 1, event_kind: "turn_todo_item_started", summary: "Started the board projection.")

    assert_sql_query_count_at_most(1) do
      feed = ConversationSupervision::BuildActivityFeed.call(conversation: context[:conversation])

      assert_equal [context[:turn].public_id], feed.map { |entry| entry.fetch("turn_id") }.uniq
    end
  end

  test "returns the latest completed turn feed when no newer turn has started" do
    context = build_agent_control_context!
    context[:turn].update!(lifecycle_state: "completed")
    create_feed_entry!(context:, turn: context[:turn], sequence: 1, event_kind: "turn_completed", summary: "Finished the current turn.")

    feed = ConversationSupervision::BuildActivityFeed.call(conversation: context[:conversation])

    assert_equal [context[:turn].public_id], feed.map { |entry| entry.fetch("turn_id") }.uniq
    assert_equal ["turn_completed"], feed.map { |entry| entry.fetch("event_kind") }
  end

  test "returns the newest active turn feed when multiple active turns exist" do
    context = build_agent_control_context!
    newer_turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "A newer active turn",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_feed_entry!(context:, turn: context[:turn], sequence: 1, event_kind: "turn_started", summary: "Older active turn.")
    create_feed_entry!(context:, turn: newer_turn, sequence: 2, event_kind: "turn_started", summary: "Newer active turn.")

    feed = ConversationSupervision::BuildActivityFeed.call(conversation: context[:conversation])

    assert_equal [newer_turn.public_id], feed.map { |entry| entry.fetch("turn_id") }.uniq
    assert_equal ["Newer active turn."], feed.map { |entry| entry.fetch("summary") }
  end

  test "prefers the persisted latest active turn anchor over scan ordering" do
    context = build_agent_control_context!
    newer_turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "A newer active turn",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_feed_entry!(context:, turn: context[:turn], sequence: 1, event_kind: "turn_started", summary: "Anchored turn.")
    create_feed_entry!(context:, turn: newer_turn, sequence: 2, event_kind: "turn_started", summary: "Scanned newer turn.")
    context[:conversation].update!(latest_active_turn_id: context[:turn].id)

    feed = ConversationSupervision::BuildActivityFeed.call(conversation: context[:conversation])

    assert_equal [context[:turn].public_id], feed.map { |entry| entry.fetch("turn_id") }.uniq
    assert_equal ["Anchored turn."], feed.map { |entry| entry.fetch("summary") }
  end

  test "keeps the supervision feed surface while avoiding synthetic turn todo fallback for provider-backed work" do
    fixture = prepare_provider_backed_conversation_supervision_context!

    feed = ConversationSupervision::BuildActivityFeed.call(conversation: fixture.fetch(:conversation))

    refute feed.any? { |entry| entry.fetch("event_kind").start_with?("turn_todo_") }
    assert_includes feed.map { |entry| entry.fetch("event_kind") }, "turn_started"
    refute_match(/provider round|command_run_wait|exec_command|React app|game files/i, feed.to_json)
  end

  private

  def create_feed_entry!(context:, turn:, sequence:, event_kind:, summary:)
    ConversationSupervisionFeedEntry.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
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
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      agent_definition_version: template_turn.agent_definition_version,
      execution_runtime: template_turn.execution_runtime,
      sequence: sequence,
      lifecycle_state: lifecycle_state,
      origin_kind: "system_internal",
      origin_payload: {},
      pinned_agent_definition_fingerprint: template_turn.agent_definition_version.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
  end
end
