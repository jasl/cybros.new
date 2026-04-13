require "test_helper"

class ConversationSupervision::PruneFeedWindowTest < ActiveSupport::TestCase
  test "removes feed rows outside the latest two turns once a newer turn has written feed" do
    context = build_agent_control_context!
    turn_one = context[:turn]
    turn_one.update!(lifecycle_state: "completed")
    turn_two = create_feed_turn!(
      conversation: context[:conversation],
      template_turn: turn_one,
      sequence: 2,
      lifecycle_state: "completed"
    )
    turn_three = create_feed_turn!(
      conversation: context[:conversation],
      template_turn: turn_one,
      sequence: 3,
      lifecycle_state: "active"
    )

    create_feed_entry!(context:, turn: turn_one, sequence: 1, summary: "Turn one")
    create_feed_entry!(context:, turn: turn_two, sequence: 2, summary: "Turn two")
    create_feed_entry!(context:, turn: turn_three, sequence: 3, summary: "Turn three")

    ConversationSupervision::PruneFeedWindow.call(conversation: context[:conversation])

    assert_equal [turn_two.public_id, turn_three.public_id].sort,
      ConversationSupervisionFeedEntry.order(:sequence).pluck(:target_turn_id).map { |id| Turn.find(id).public_id }.uniq.sort
  end

  private

  def create_feed_entry!(context:, turn:, sequence:, summary:)
    ConversationSupervisionFeedEntry.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
      target_turn: turn,
      sequence: sequence,
      event_kind: "turn_todo_item_started",
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
      execution_runtime_version: template_turn.execution_runtime_version,
      sequence: sequence,
      lifecycle_state: lifecycle_state,
      origin_kind: "system_internal",
      origin_payload: {},
      pinned_agent_definition_fingerprint: template_turn.agent_definition_version.definition_fingerprint,
      agent_config_version: template_turn.agent_config_version,
      agent_config_content_fingerprint: template_turn.agent_config_content_fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
  end
end
