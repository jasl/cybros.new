require "test_helper"

class Publications::LiveProjectionTest < ActiveSupport::TestCase
  test "returns transcript messages and visible conversation events in deterministic live order" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish this conversation",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Published output")
    ConversationEvents::Project.call(
      conversation: conversation,
      turn: turn,
      event_kind: "runtime.status",
      stream_key: "status-card",
      payload: { "state" => "waiting" }
    )
    streamed_revision = ConversationEvents::Project.call(
      conversation: conversation,
      turn: turn,
      event_kind: "runtime.status",
      stream_key: "status-card",
      payload: { "state" => "resolved" }
    )
    plain = ConversationEvents::Project.call(
      conversation: conversation,
      event_kind: "runtime.notice",
      payload: { "state" => "done" }
    )
    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "external_public"
    )

    entries = Publications::LiveProjection.call(publication: publication)

    assert_equal %w[message conversation_event message conversation_event], entries.map(&:entry_type)
    assert_equal turn.selected_input_message, entries[0].record
    assert_equal streamed_revision, entries[1].record
    assert_equal output, entries[2].record
    assert_equal plain, entries[3].record
    assert_equal "resolved", entries[1].record.payload["state"]
  end
end
