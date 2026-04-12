require "test_helper"

class Conversations::Metadata::BootstrapTitleTest < ActiveSupport::TestCase
  test "first user message sets conversation title metadata" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    message = create_user_input_message!(
      context: context,
      conversation: conversation,
      content: "Plan the launch checklist. Include rollback steps."
    )
    occurred_at = Time.zone.parse("2026-04-06 10:00:00")

    Conversations::Metadata::BootstrapTitle.call(
      conversation: conversation,
      message: message,
      occurred_at: occurred_at
    )

    conversation.reload
    assert_equal "Plan the launch checklist.", conversation.title
    assert_equal "bootstrap", conversation.title_source
    assert_equal occurred_at, conversation.title_updated_at
  end

  test "later user turns do not replace an existing title" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    first_message = create_user_input_message!(
      context: context,
      conversation: conversation,
      content: "Draft release notes."
    )
    later_message = create_user_input_message!(
      context: context,
      conversation: conversation,
      content: "Rename this to something else."
    )
    first_time = Time.zone.parse("2026-04-06 10:00:00")
    later_time = Time.zone.parse("2026-04-06 10:05:00")

    Conversations::Metadata::BootstrapTitle.call(
      conversation: conversation,
      message: first_message,
      occurred_at: first_time
    )
    Conversations::Metadata::BootstrapTitle.call(
      conversation: conversation,
      message: later_message,
      occurred_at: later_time
    )

    conversation.reload
    assert_equal "Draft release notes.", conversation.title
    assert_equal first_time, conversation.title_updated_at
  end

  test "blank input falls back to a neutral untitled title" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    message = UserMessage.new(
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "  \n\t  "
    )

    Conversations::Metadata::BootstrapTitle.call(
      conversation: conversation,
      message: message
    )

    conversation.reload
    assert_equal "Untitled conversation", conversation.title
    assert_equal "bootstrap", conversation.title_source
    assert_not_nil conversation.title_updated_at
  end

  test "locked titles are not overwritten" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    locked_time = Time.zone.parse("2026-04-06 09:00:00")
    conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked",
      title_updated_at: locked_time
    )
    message = create_user_input_message!(
      context: context,
      conversation: conversation,
      content: "Attempt to overwrite locked title."
    )

    Conversations::Metadata::BootstrapTitle.call(
      conversation: conversation,
      message: message,
      occurred_at: Time.zone.parse("2026-04-06 10:00:00")
    )

    conversation.reload
    assert_equal "Pinned title", conversation.title
    assert_equal "user", conversation.title_source
    assert_equal "user_locked", conversation.title_lock_state
    assert_equal locked_time, conversation.title_updated_at
  end

  private

  def create_user_input_message!(context:, conversation:, content:)
    agent_config_state = context[:agent].agent_config_state

    turn = Turn.create!(
      installation: conversation.installation,
      conversation: conversation,
      agent_definition_version: context[:agent_definition_version],
      execution_runtime: context[:execution_runtime],
      sequence: conversation.turns.maximum(:sequence).to_i + 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      source_ref_type: "User",
      source_ref_id: context[:user].public_id,
      pinned_agent_definition_fingerprint: context[:agent_definition_version].definition_fingerprint,
      agent_config_version: agent_config_state&.version || 1,
      agent_config_content_fingerprint: agent_config_state&.content_fingerprint || context[:agent_definition_version].definition_fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    UserMessage.create!(
      installation: conversation.installation,
      conversation: conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: content
    )
  end
end
