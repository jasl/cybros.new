require "test_helper"

class AgentControl::CreateAgentProgramRequestTest < ActiveSupport::TestCase
  test "creates and publishes a deployment-targeted mailbox request for the agent program" do
    context = build_agent_control_context!
    published = []
    original_publish_pending = AgentControl::PublishPending.method(:call)

    AgentControl::PublishPending.singleton_class.define_method(:call) do |mailbox_item:|
      published << mailbox_item
      mailbox_item
    end

    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_deployment: context.fetch(:deployment),
      request_kind: "prepare_round",
      payload: {
        "workflow_node_id" => context.fetch(:workflow_node).public_id,
        "conversation_id" => context.fetch(:conversation).public_id,
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}",
      attempt_no: 2,
      dispatch_deadline_at: 5.minutes.from_now
    )

    assert_equal "agent_program_request", mailbox_item.item_type
    assert_equal "agent", mailbox_item.runtime_plane
    assert_equal "agent_deployment", mailbox_item.target_kind
    assert_equal context.fetch(:deployment), mailbox_item.target_agent_deployment
    assert_equal context.fetch(:agent_installation), mailbox_item.target_agent_installation
    assert_equal "prepare_round", mailbox_item.payload.fetch("request_kind")
    assert_equal 2, mailbox_item.attempt_no
    assert_equal [mailbox_item], published
  ensure
    AgentControl::PublishPending.singleton_class.define_method(:call, original_publish_pending) if original_publish_pending
  end
end
