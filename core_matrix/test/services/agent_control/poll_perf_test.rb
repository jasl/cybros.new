require "test_helper"

class AgentControlPollPerfTest < ActiveSupport::TestCase
  test "publishes poll completion and mailbox lease perf events" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    poll_events = []
    lease_events = []

    ActiveSupport::Notifications.subscribed(->(*args) { poll_events << args.last }, "perf.agent_control.poll") do
      ActiveSupport::Notifications.subscribed(->(*args) { lease_events << args.last }, "perf.agent_control.mailbox_item_leased") do
        deliveries = AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

        assert_equal [scenario.fetch(:mailbox_item).id], deliveries.map(&:id)
      end
    end

    assert_equal 1, poll_events.length
    assert_equal true, poll_events.first.fetch("success")
    assert_equal context[:agent_program].public_id, poll_events.first.fetch("agent_program_public_id")
    assert_equal context[:agent_session].public_id, poll_events.first.fetch("agent_session_public_id")
    assert_equal "program", poll_events.first.fetch("control_plane")
    assert_equal 1, poll_events.first.fetch("delivery_count")

    assert_equal 1, lease_events.length
    assert_equal scenario.fetch(:mailbox_item).public_id, lease_events.first.fetch("mailbox_item_public_id")
    assert_equal context[:agent_program].public_id, lease_events.first.fetch("agent_program_public_id")
    assert_equal context[:agent_session].public_id, lease_events.first.fetch("agent_session_public_id")
    assert_equal "execution_assignment", lease_events.first.fetch("item_type")
    assert_operator lease_events.first.fetch("lease_latency_ms"), :>=, 0.0
  end
end
