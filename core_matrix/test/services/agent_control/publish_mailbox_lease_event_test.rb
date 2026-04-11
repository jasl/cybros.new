require "test_helper"

class AgentControlPublishMailboxLeaseEventTest < ActiveSupport::TestCase
  test "publishes a agent-plane mailbox lease event with public identifiers" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_request!(
      context: context,
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "kind" => "turn_step",
        },
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}"
    )
    mailbox_item = scenario.fetch(:mailbox_item)
    mailbox_item.update!(
      status: "leased",
      leased_at: mailbox_item.available_at + 0.25.seconds,
      lease_expires_at: mailbox_item.available_at + 30.seconds,
      leased_to_agent_connection: context.fetch(:agent_connection),
      delivery_no: 1
    )
    events = []

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.agent_control.mailbox_item_leased") do
      AgentControl::PublishMailboxLeaseEvent.call(
        mailbox_item: mailbox_item,
        agent_public_id: context.fetch(:agent).public_id,
        agent_connection_public_id: context.fetch(:agent_connection).public_id
      )
    end

    assert_equal 1, events.length
    assert_equal mailbox_item.public_id, events.first.fetch("mailbox_item_public_id")
    assert_equal "agent_request", events.first.fetch("item_type")
    assert_equal "agent", events.first.fetch("control_plane")
    assert_equal context.fetch(:agent).public_id, events.first.fetch("agent_public_id")
    assert_equal context.fetch(:agent_connection).public_id, events.first.fetch("agent_connection_public_id")
    assert_equal 250.0, events.first.fetch("lease_latency_ms")
  end

  test "publishes an execution-runtime-plane mailbox lease event with execution runtime connection public id" do
    context = build_rotated_runtime_context!
    other_agent = create_agent!(installation: context.fetch(:installation))
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context.fetch(:installation),
      target_agent: other_agent,
      target_execution_runtime: context.fetch(:execution_runtime),
      item_type: "resource_close_request",
      control_plane: "execution_runtime",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )
    mailbox_item.update!(
      status: "leased",
      leased_at: mailbox_item.available_at + 0.1.seconds,
      lease_expires_at: mailbox_item.available_at + 30.seconds,
      leased_to_execution_runtime_connection: context.fetch(:execution_runtime_connection),
      delivery_no: 1
    )
    events = []

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.agent_control.mailbox_item_leased") do
      AgentControl::PublishMailboxLeaseEvent.call(
        mailbox_item: mailbox_item,
        execution_runtime_connection_public_id: context.fetch(:execution_runtime_connection).public_id
      )
    end

    assert_equal 1, events.length
    assert_equal mailbox_item.public_id, events.first.fetch("mailbox_item_public_id")
    assert_equal "resource_close_request", events.first.fetch("item_type")
    assert_equal "execution_runtime", events.first.fetch("control_plane")
    assert_equal context.fetch(:execution_runtime_connection).public_id, events.first.fetch("execution_runtime_connection_public_id")
    refute events.first.key?("agent_public_id")
  end
end
