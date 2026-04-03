require "test_helper"

class AgentControlPublishPendingTest < ActiveSupport::TestCase
  test "publishes execution-plane work for an execution session using durable execution runtime routing" do
    context = build_rotated_runtime_context!
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      runtime_plane: "execution",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )

    broadcasts = []

    with_captured_broadcasts(broadcasts) do
      AgentControl::PublishPending.call(execution_session: context[:execution_session])
    end

    assert_equal [[AgentControl::StreamName.for_deployment(context[:execution_session]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:execution_session], mailbox_item.reload.leased_to_execution_session
  end

  test "publishes a queued mailbox item to the deployment selected by ResolveTargetRuntime" do
    context = build_agent_control_context!
    context[:execution_session].update!(endpoint_metadata: { "realtime_link_connected" => true })
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      runtime_plane: "execution",
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

    assert_equal [[AgentControl::StreamName.for_deployment(context[:execution_session]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:execution_session], mailbox_item.reload.leased_to_execution_session
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
