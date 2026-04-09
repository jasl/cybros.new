require "test_helper"

class AgentControlPublishPendingTest < ActiveSupport::TestCase
  test "publishes executor-plane work for an executor session using durable executor program routing" do
    context = build_rotated_runtime_context!
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_executor_program: context[:executor_program],
      item_type: "resource_close_request",
      control_plane: "executor",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )

    broadcasts = []

    with_captured_broadcasts(broadcasts) do
      AgentControl::PublishPending.call(executor_session: context[:executor_session])
    end

    assert_equal [[AgentControl::StreamName.for_deployment(context[:executor_session]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:executor_session], mailbox_item.reload.leased_to_executor_session
  end

  test "publishes a queued mailbox item to the deployment selected by ResolveTargetRuntime" do
    context = build_agent_control_context!
    context[:executor_session].update!(endpoint_metadata: { "realtime_link_connected" => true })
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_executor_program: context[:executor_program],
      item_type: "resource_close_request",
      control_plane: "executor",
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

    assert_equal [[AgentControl::StreamName.for_deployment(context[:executor_session]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:executor_session], mailbox_item.reload.leased_to_executor_session
  end

  test "publishes a mailbox lease event when realtime-connected routing broadcasts a program-plane mailbox item" do
    context = build_agent_control_context!
    context[:agent_session].update!(endpoint_metadata: { "realtime_link_connected" => true })
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      target_agent_program_version: context[:deployment],
      item_type: "agent_program_request",
      control_plane: "program",
      payload: {
        "request_kind" => "prepare_round",
        "runtime_context" => {
          "agent_program_id" => context[:agent_program].public_id,
          "agent_program_version_id" => context[:deployment].public_id,
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

    assert_equal [[AgentControl::StreamName.for_deployment(context[:deployment]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal 1, lease_events.length
    assert_equal mailbox_item.public_id, lease_events.first.fetch("mailbox_item_public_id")
    assert_equal context[:agent_program].public_id, lease_events.first.fetch("agent_program_public_id")
    assert_equal context[:agent_session].public_id, lease_events.first.fetch("agent_session_public_id")
  end

  test "publishes a materialized program-plane mailbox item without runtime re-resolution" do
    context = build_agent_control_context!
    context[:agent_session].update!(endpoint_metadata: { "realtime_link_connected" => true })
    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_program_version: context.fetch(:deployment),
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

    assert_equal [[AgentControl::StreamName.for_deployment(context[:deployment]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:agent_session], mailbox_item.reload.leased_to_agent_session
  ensure
    AgentControl::ResolveTargetRuntime.singleton_class.define_method(:call, original_call) if original_call
  end

  test "does not publish a duplicate mailbox lease event when a realtime-connected mailbox item is already leased" do
    context = build_agent_control_context!
    context[:agent_session].update!(endpoint_metadata: { "realtime_link_connected" => true })
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      target_agent_program_version: context[:deployment],
      item_type: "agent_program_request",
      control_plane: "program",
      payload: { "request_kind" => "prepare_round" }
    )
    now = Time.current
    mailbox_item.update!(
      status: "leased",
      leased_to_agent_session: context[:agent_session],
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
    context[:executor_session].update!(endpoint_metadata: { "realtime_link_connected" => true })
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_executor_program: context[:executor_program],
      item_type: "resource_close_request",
      control_plane: "executor",
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
