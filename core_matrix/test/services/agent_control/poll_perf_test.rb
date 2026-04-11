require "test_helper"

class AgentControlPollPerfTest < ActiveSupport::TestCase
  test "publishes poll completion and mailbox lease perf events" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_request!(
      context: context,
      request_kind: "prepare_round",
      logical_work_id: "prepare-round-poll-perf",
      payload: {
        "request_kind" => "prepare_round",
        "task" => {
          "workflow_node_id" => context[:workflow_node].public_id,
          "workflow_run_id" => context[:workflow_run].public_id,
          "conversation_id" => context[:conversation].public_id,
          "turn_id" => context[:turn].public_id,
          "kind" => context[:workflow_node].node_type,
        },
      }
    )
    poll_events = []
    lease_events = []

    ActiveSupport::Notifications.subscribed(->(*args) { poll_events << args.last }, "perf.agent_control.poll") do
      ActiveSupport::Notifications.subscribed(->(*args) { lease_events << args.last }, "perf.agent_control.mailbox_item_leased") do
        deliveries = AgentControl::Poll.call(agent_snapshot: context[:agent_snapshot], limit: 10)

        assert_equal [scenario.fetch(:mailbox_item).id], deliveries.map(&:id)
      end
    end

    assert_equal 1, poll_events.length
    assert_equal true, poll_events.first.fetch("success")
    assert_equal context[:agent].public_id, poll_events.first.fetch("agent_public_id")
    assert_equal context[:agent_connection].public_id, poll_events.first.fetch("agent_connection_public_id")
    assert_equal "agent", poll_events.first.fetch("control_plane")
    assert_equal 1, poll_events.first.fetch("delivery_count")

    assert_equal 1, lease_events.length
    assert_equal scenario.fetch(:mailbox_item).public_id, lease_events.first.fetch("mailbox_item_public_id")
    assert_equal context[:agent].public_id, lease_events.first.fetch("agent_public_id")
    assert_equal context[:agent_connection].public_id, lease_events.first.fetch("agent_connection_public_id")
    assert_equal "agent_request", lease_events.first.fetch("item_type")
    assert_operator lease_events.first.fetch("lease_latency_ms"), :>=, 0.0
  end
end
