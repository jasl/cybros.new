require "test_helper"

class AgentControlPublishPendingTest < ActiveSupport::TestCase
  test "publishes environment-plane work for a deployment using durable execution environment routing" do
    context = build_rotated_runtime_context!
    other_agent_installation = create_agent_installation!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_installation: other_agent_installation,
      target_execution_environment: context[:execution_environment],
      item_type: "resource_close_request",
      runtime_plane: "environment",
      target_kind: "agent_installation",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )

    broadcasts = []

    with_captured_broadcasts(broadcasts) do
      AgentControl::PublishPending.call(deployment: context[:replacement_deployment])
    end

    assert_equal [[AgentControl::StreamName.for_deployment(context[:replacement_deployment]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:replacement_deployment], mailbox_item.reload.leased_to_agent_deployment
  end

  test "publishes a queued mailbox item to the deployment selected by ResolveTargetRuntime" do
    context = build_agent_control_context!
    context[:deployment].update!(realtime_link_state: "connected")
    other_agent_installation = create_agent_installation!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_installation: other_agent_installation,
      target_execution_environment: context[:execution_environment],
      item_type: "resource_close_request",
      runtime_plane: "environment",
      target_kind: "agent_installation",
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

    assert_equal [[AgentControl::StreamName.for_deployment(context[:deployment]), mailbox_item.public_id]],
      broadcasts.map { |stream, payload| [stream, payload.fetch("item_id")] }
    assert_equal context[:deployment], mailbox_item.reload.leased_to_agent_deployment
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
