require "test_helper"

class AgentControl::SerializeMailboxItemsTest < ActiveSupport::TestCase
  test "serializes materialized agent requests with frozen workspace agent documents without query explosion" do
    mailbox_items = 3.times.map do |index|
      context = build_agent_control_context!(
        workspace_agent_global_instructions: "Use concise Chinese.\n",
        workspace_agent_settings_payload: {
          "interactive" => {
            "profile_key" => "friendly",
          },
          "subagents" => {
            "enabled_profile_keys" => ["developer"],
            "default_profile_key" => "developer",
          },
        }
      )
      build_execution_snapshot_for!(
        turn: context.fetch(:turn),
        selector_source: "test",
        selector: "role:mock"
      )

      AgentControl::CreateAgentRequest.call(
        agent_definition_version: context.fetch(:agent_definition_version),
        request_kind: "prepare_round",
        payload: {
          "task" => {
            "kind" => "turn_step",
            "turn_id" => context.fetch(:turn).public_id,
            "conversation_id" => context.fetch(:conversation).public_id,
            "workflow_run_id" => context.fetch(:workflow_run).public_id,
            "workflow_node_id" => context.fetch(:workflow_node).public_id,
          },
        },
        logical_work_id: "prepare-round-batch-#{index}",
        attempt_no: 1,
        dispatch_deadline_at: 5.minutes.from_now
      )
    end

    single_item_queries = capture_sql_queries do
      serialized = AgentControl::SerializeMailboxItems.call(mailbox_items.first)

      assert_equal 1, serialized.length
    end

    batch_queries = capture_sql_queries do
      serialized = AgentControl::SerializeMailboxItems.call(mailbox_items)

      assert_equal 3, serialized.length
      serialized.each do |payload|
        assert_equal "friendly", payload.dig("payload", "workspace_agent_context", "settings_payload", "interactive", "profile_key")
        assert_equal "Use concise Chinese.\n", payload.dig("payload", "workspace_agent_context", "global_instructions")
      end
    end

    query_growth = batch_queries.length - single_item_queries.length

    assert_operator query_growth,
      :<=,
      10,
      "Expected batched mailbox serialization to add at most 10 SQL queries over the single-item baseline, got #{query_growth} additional queries.\nSingle-item queries (#{single_item_queries.length}):\n#{single_item_queries.join("\n")}\n\nBatch queries (#{batch_queries.length}):\n#{batch_queries.join("\n")}"
  end
end
