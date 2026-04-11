require "test_helper"

class AgentControlPublishPendingTest < ActiveSupport::TestCase
  test "publishes execution-runtime-plane work for an execution runtime connection using durable execution runtime routing" do
    context = build_rotated_runtime_context!
    other_agent = create_agent!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: other_agent,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      control_plane: "execution_runtime",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )

    broadcasts = []

    with_captured_broadcasts(broadcasts) do
      AgentControl::PublishPending.call(execution_runtime_connection: context[:execution_runtime_connection])
    end

    assert_equal [[AgentControl::StreamName.for_delivery_endpoint(context[:execution_runtime_connection]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:execution_runtime_connection], mailbox_item.reload.leased_to_execution_runtime_connection
  end

  test "publishes a queued mailbox item to the agent_snapshot selected by ResolveTargetRuntime" do
    context = build_agent_control_context!
    context[:execution_runtime_connection].update!(endpoint_metadata: { "realtime_link_connected" => true })
    other_agent = create_agent!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: other_agent,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      control_plane: "execution_runtime",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )

    broadcasts = []

    with_captured_broadcasts(broadcasts) do
      AgentControl::PublishPending.call(mailbox_item: mailbox_item)
    end

    assert_equal [[AgentControl::StreamName.for_delivery_endpoint(context[:execution_runtime_connection]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:execution_runtime_connection], mailbox_item.reload.leased_to_execution_runtime_connection
  end

  test "publishes a mailbox lease event when realtime-connected routing broadcasts a agent-plane mailbox item" do
    context = build_agent_control_context!
    context[:agent_connection].update!(endpoint_metadata: { "realtime_link_connected" => true })
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: context[:agent],
      target_agent_snapshot: context[:agent_snapshot],
      item_type: "agent_request",
      control_plane: "agent",
      payload: {
        "request_kind" => "prepare_round",
        "runtime_context" => {
          "agent_id" => context[:agent].public_id,
          "agent_snapshot_id" => context[:agent_snapshot].public_id,
          "user_id" => context[:user].public_id,
        },
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
    broadcasts = []
    lease_events = []

    ActiveSupport::Notifications.subscribed(->(*args) { lease_events << args.last }, "perf.agent_control.mailbox_item_leased") do
      with_captured_broadcasts(broadcasts) do
        AgentControl::PublishPending.call(mailbox_item: mailbox_item)
      end
    end

    assert_equal [[AgentControl::StreamName.for_delivery_endpoint(context[:agent_snapshot]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal 1, lease_events.length
    assert_equal mailbox_item.public_id, lease_events.first.fetch("mailbox_item_public_id")
    assert_equal context[:agent].public_id, lease_events.first.fetch("agent_public_id")
    assert_equal context[:agent_connection].public_id, lease_events.first.fetch("agent_connection_public_id")
  end

  test "publishes a materialized agent-plane mailbox item without runtime re-resolution" do
    context = build_agent_control_context!
    context[:agent_connection].update!(endpoint_metadata: { "realtime_link_connected" => true })
    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_snapshot: context.fetch(:agent_snapshot),
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
          "turn_id" => context.fetch(:turn).public_id,
        },
      },
      logical_work_id: "prepare-round:materialized-publish",
      dispatch_deadline_at: 5.minutes.from_now
    )
    original_call = AgentControl::ResolveTargetRuntime.method(:call)

    AgentControl::ResolveTargetRuntime.singleton_class.define_method(:call) do |**|
      raise "ResolveTargetRuntime.call should not be used for materialized single-item publish"
    end

    broadcasts = []

    with_captured_broadcasts(broadcasts) do
      AgentControl::PublishPending.call(mailbox_item: mailbox_item)
    end

    assert_equal [[AgentControl::StreamName.for_delivery_endpoint(context[:agent_snapshot]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:agent_connection], mailbox_item.reload.leased_to_agent_connection
  ensure
    AgentControl::ResolveTargetRuntime.singleton_class.define_method(:call, original_call) if original_call
  end

  test "does not publish a duplicate mailbox lease event when a realtime-connected mailbox item is already leased" do
    context = build_agent_control_context!
    context[:agent_connection].update!(endpoint_metadata: { "realtime_link_connected" => true })
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: context[:agent],
      target_agent_snapshot: context[:agent_snapshot],
      item_type: "agent_request",
      control_plane: "agent",
      payload: { "request_kind" => "prepare_round" }
    )
    now = Time.current
    mailbox_item.update!(
      status: "leased",
      leased_to_agent_connection: context[:agent_connection],
      leased_at: now,
      lease_expires_at: now + mailbox_item.lease_timeout_seconds.seconds,
      delivery_no: 1
    )
    lease_events = []

    ActiveSupport::Notifications.subscribed(->(*args) { lease_events << args.last }, "perf.agent_control.mailbox_item_leased") do
      with_captured_broadcasts([]) do
        AgentControl::PublishPending.call(mailbox_item: mailbox_item)
      end
    end

    assert_empty lease_events
  end

  test "publishes a queued mailbox item without single-item routing query explosion" do
    context = build_agent_control_context!
    context[:execution_runtime_connection].update!(endpoint_metadata: { "realtime_link_connected" => true })
    other_agent = create_agent!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: other_agent,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      control_plane: "execution_runtime",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )

    queries = capture_sql_queries do
      with_captured_broadcasts([]) do
        AgentControl::PublishPending.call(mailbox_item: mailbox_item)
      end
    end

    assert_operator queries.length, :<=, 6, "Expected single-item publish to stay under 6 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end

  private

  def with_captured_broadcasts(broadcasts)
    singleton = ActionCable.server.singleton_class
    original_broadcast = ActionCable.server.method(:broadcast)

    singleton.send(:define_method, :broadcast) do |stream, payload|
      broadcasts << [stream, payload]
    end

    yield
  ensure
    singleton.send(:define_method, :broadcast, original_broadcast)
  end
end
