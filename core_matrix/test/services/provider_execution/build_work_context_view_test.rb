require "test_helper"

class ProviderExecution::BuildWorkContextViewTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "builds a neutral work context view from durable plan and supervision state" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!

    view = ProviderExecution::BuildWorkContextView.call(
      workflow_node: fixture.fetch(:workflow_node)
    )

    assert_equal fixture.fetch(:conversation).public_id, view.fetch("conversation_id")
    assert_equal fixture.fetch(:current_turn).public_id, view.fetch("turn_id")
    assert_equal "render-snapshot",
      view.dig("primary_turn_todo", "plan_summary", "current_item_key")
    assert_equal "Rendering the frozen supervision snapshot",
      view.dig("primary_turn_todo", "plan_view", "current_item", "title")
    assert_equal [fixture.fetch(:subagent_connection).public_id],
      view.fetch("active_children").map { |entry| entry.fetch("subagent_connection_id") }
    assert_equal [fixture.fetch(:subagent_connection).conversation.public_id],
      view.fetch("active_children").map { |entry| entry.fetch("conversation_id") }
    assert_equal ["Checking the 2048 acceptance flow"],
      view.fetch("active_children").map { |entry| entry.dig("plan_summary", "current_item_title") }
    assert_equal "waiting", view.dig("supervision_snapshot", "overall_state")
    assert_equal 1, view.dig("supervision_snapshot", "active_child_count")
    refute view.key?("active_subagents")
    refute view.key?("supervisor_guidance")
    refute_match(/cowork/i, view.to_json)
  end

  test "builds active child plan summaries without depending on supervision detail policy gates" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!(
      detailed_progress_enabled: false
    )

    view = ProviderExecution::BuildWorkContextView.call(
      workflow_node: fixture.fetch(:workflow_node)
    )

    assert_equal "render-snapshot",
      view.dig("primary_turn_todo", "plan_summary", "current_item_key")
    assert_equal "check-hard-gate",
      view.dig("active_children", 0, "plan_summary", "current_item_key")
    assert_equal "Checking the 2048 acceptance flow",
      view.dig("active_children", 0, "current_focus_summary")
  end

  test "includes delivered supervisor guidance for the current runtime target" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      user: fixture.fetch(:conversation).user,
      workspace: fixture.fetch(:conversation).workspace,
      agent: fixture.fetch(:conversation).agent,
      request_kind: "send_guidance_to_active_agent",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "completed",
      request_payload: { "content" => "Stop and summarize the latest blocker." },
      result_payload: {
        "response_payload" => {
          "control_outcome" => {
            "outcome_kind" => "guidance_acknowledged",
          },
        },
      },
      completed_at: Time.current
    )

    view = ProviderExecution::BuildWorkContextView.call(
      workflow_node: fixture.fetch(:workflow_node)
    )

    assert_equal "conversation", view.dig("supervisor_guidance", "guidance_scope")
    assert_equal "Stop and summarize the latest blocker.",
      view.dig("supervisor_guidance", "latest_guidance", "content")
  end
end
