require "test_helper"

class AgentControlPublishMailboxLeaseEventTest < ActiveSupport::TestCase
  test "publishes a program-plane mailbox lease event with public identifiers" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_program_request!(
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
      leased_to_agent_session: context.fetch(:agent_session),
      delivery_no: 1
    )
    events = []

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.agent_control.mailbox_item_leased") do
      AgentControl::PublishMailboxLeaseEvent.call(
        mailbox_item: mailbox_item,
        agent_program_public_id: context.fetch(:agent_program).public_id,
        agent_session_public_id: context.fetch(:agent_session).public_id
      )
    end

    assert_equal 1, events.length
    assert_equal mailbox_item.public_id, events.first.fetch("mailbox_item_public_id")
    assert_equal "agent_program_request", events.first.fetch("item_type")
    assert_equal "program", events.first.fetch("control_plane")
    assert_equal context.fetch(:agent_program).public_id, events.first.fetch("agent_program_public_id")
    assert_equal context.fetch(:agent_session).public_id, events.first.fetch("agent_session_public_id")
    assert_equal 250.0, events.first.fetch("lease_latency_ms")
  end

  test "publishes an executor-plane mailbox lease event with executor session public id" do
    context = build_rotated_runtime_context!
    other_agent_program = create_agent_program!(installation: context.fetch(:installation))
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context.fetch(:installation),
      target_agent_program: other_agent_program,
      target_executor_program: context.fetch(:executor_program),
      item_type: "resource_close_request",
      control_plane: "executor",
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
      leased_to_executor_session: context.fetch(:executor_session),
      delivery_no: 1
    )
    events = []

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.agent_control.mailbox_item_leased") do
      AgentControl::PublishMailboxLeaseEvent.call(
        mailbox_item: mailbox_item,
        executor_session_public_id: context.fetch(:executor_session).public_id
      )
    end

    assert_equal 1, events.length
    assert_equal mailbox_item.public_id, events.first.fetch("mailbox_item_public_id")
    assert_equal "resource_close_request", events.first.fetch("item_type")
    assert_equal "executor", events.first.fetch("control_plane")
    assert_equal context.fetch(:executor_session).public_id, events.first.fetch("executor_session_public_id")
    refute events.first.key?("agent_program_public_id")
  end
end
