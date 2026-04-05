require "test_helper"

class AgentControl::CreateAgentProgramRequestTest < ActiveSupport::TestCase
  test "creates and publishes a program-version-targeted mailbox request for the agent program" do
    context = build_agent_control_context!
    published = []
    original_publish_pending = AgentControl::PublishPending.method(:call)

    AgentControl::PublishPending.singleton_class.define_method(:call) do |mailbox_item:|
      published << mailbox_item
      mailbox_item
    end

    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_program_version: context.fetch(:deployment),
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
    assert_equal "program", mailbox_item.runtime_plane
    refute_respond_to mailbox_item, :target_kind
    assert_equal context.fetch(:deployment), mailbox_item.target_agent_program_version
    assert_equal context.fetch(:agent_program), mailbox_item.target_agent_program
    assert_equal "prepare_round", mailbox_item.payload.fetch("request_kind")
    assert_equal({ "request_kind" => "prepare_round" }, mailbox_item.payload_body)
    assert_equal "agent_program_request", mailbox_item.payload_document.document_kind
    assert_equal 2, mailbox_item.attempt_no
    assert_equal [mailbox_item], published
  ensure
    AgentControl::PublishPending.singleton_class.define_method(:call, original_publish_pending) if original_publish_pending
  end

  test "stores only the request body in the payload document and reconstructs structured runtime context on read" do
    context = build_agent_control_context!
    logical_work_id = "prepare-round:#{context.fetch(:workflow_node).public_id}"

    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_program_version: context.fetch(:deployment),
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
        "runtime_context" => {
          "logical_work_id" => logical_work_id,
          "attempt_no" => 3,
          "runtime_plane" => "program",
          "agent_program_version_id" => context.fetch(:deployment).public_id,
          "custom_flag" => "keep-me",
        },
      },
      logical_work_id: logical_work_id,
      attempt_no: 3,
      dispatch_deadline_at: 5.minutes.from_now
    )

    stored_payload = mailbox_item.payload_document.payload

    refute stored_payload.key?("request_kind")
    assert_equal({ "custom_flag" => "keep-me" }, stored_payload.fetch("runtime_context"))
    assert_equal "prepare_round", mailbox_item.payload.fetch("request_kind")
    assert_equal logical_work_id, mailbox_item.payload.dig("runtime_context", "logical_work_id")
    assert_equal 3, mailbox_item.payload.dig("runtime_context", "attempt_no")
    assert_equal "program", mailbox_item.payload.dig("runtime_context", "runtime_plane")
    assert_equal context.fetch(:deployment).public_id, mailbox_item.payload.dig("runtime_context", "agent_program_version_id")
    assert_equal "keep-me", mailbox_item.payload.dig("runtime_context", "custom_flag")
  end
end
