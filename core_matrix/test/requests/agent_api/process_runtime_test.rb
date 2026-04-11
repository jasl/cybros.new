require "test_helper"
require "action_cable/test_helper"

class AgentApiProcessRuntimeTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  test "process_started marks a starting process run as running" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      lifecycle_state: "starting",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_runtime_connection].public_id,
      heartbeat_timeout_seconds: 30
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      post "/execution_runtime_api/control/report",
        params: {
          method_id: "process_started",
          protocol_message_id: "process-started-#{next_test_sequence}",
          resource_type: "ProcessRun",
          resource_id: process_run.public_id,
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
        as: :json
    end

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal ["runtime.process_run.started"], broadcasts.map { |payload| payload.fetch("event_kind") }
    assert process_run.reload.running?
  end

  test "process_output streams stdout chunks without persisting them" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_runtime_connection].public_id,
      heartbeat_timeout_seconds: 30
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      post "/execution_runtime_api/control/report",
        params: {
          method_id: "process_output",
          protocol_message_id: "process-output-#{next_test_sequence}",
          resource_type: "ProcessRun",
          resource_id: process_run.public_id,
          output_chunks: [
            { "stream" => "stdout", "text" => "hello from process\n" },
          ],
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
        as: :json
    end

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal ["runtime.process_run.output"], broadcasts.map { |payload| payload.fetch("event_kind") }
    assert_equal "stdout", broadcasts.first.dig("payload", "stream")
    assert_equal "hello from process\n", broadcasts.first.dig("payload", "text")
    assert process_run.reload.running?
    assert_equal({}, process_run.close_outcome_payload)
  end

  test "process_exited terminalizes a running process without a close request" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_runtime_connection].public_id,
      heartbeat_timeout_seconds: 30
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      post "/execution_runtime_api/control/report",
        params: {
          method_id: "process_exited",
          protocol_message_id: "process-exited-#{next_test_sequence}",
          resource_type: "ProcessRun",
          resource_id: process_run.public_id,
          lifecycle_state: "failed",
          exit_status: 127,
          metadata: {
            "source" => "process_runtime_test",
            "reason" => "natural_exit",
          },
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
        as: :json
    end

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal ["runtime.process_run.failed"], broadcasts.map { |payload| payload.fetch("event_kind") }
    assert process_run.reload.failed?
    assert_equal 127, process_run.exit_status
    assert_equal "natural_exit", process_run.metadata["stop_reason"]
    assert_equal 0, ToolInvocation.count
  end

  test "process_exited settles an outstanding close request instead of leaving the process close pending" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_runtime_connection].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    post "/execution_runtime_api/control/report",
      params: {
        method_id: "process_exited",
        protocol_message_id: "process-exited-close-#{next_test_sequence}",
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        lifecycle_state: "stopped",
        exit_status: 0,
        metadata: {
          "source" => "process_runtime_test",
          "reason" => "natural_exit",
        },
      },
      headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
      as: :json

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")

    process_run.reload
    assert_equal "stopped", process_run.lifecycle_state
    assert_equal "closed", process_run.close_state
    assert_equal "graceful", process_run.close_outcome_kind
    assert_equal "completed", close_request.reload.status
  end

  test "resource_closed broadcasts final output chunks and terminal process state without creating tool invocations" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_runtime_connection].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    close_request = AgentControl::Poll.call(
      execution_runtime_connection: context[:execution_runtime_connection],
      limit: 10
    ).find do |mailbox_item|
      mailbox_item.public_id == close_request.public_id
    end
    stream_name = ConversationRuntime::StreamName.for_conversation(context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      post "/execution_runtime_api/control/report",
        params: {
          method_id: "resource_closed",
          protocol_message_id: "process-close-#{next_test_sequence}",
          mailbox_item_id: close_request.public_id,
          close_request_id: close_request.public_id,
          resource_type: "ProcessRun",
          resource_id: process_run.public_id,
          close_outcome_kind: "graceful",
          close_outcome_payload: { "source" => "process_runtime_test" },
          output_chunks: [
            { "stream" => "stdout", "text" => "goodbye from process\n" },
          ],
        },
        headers: execution_runtime_api_headers(context[:execution_runtime_connection_credential]),
        as: :json
    end

    assert_response :success
    assert_equal "accepted", JSON.parse(response.body).fetch("result")
    assert_equal %w[runtime.process_run.output runtime.process_run.stopped], broadcasts.map { |payload| payload.fetch("event_kind") }
    assert_equal "goodbye from process\n", broadcasts.first.dig("payload", "text")
    assert_equal "closed", process_run.reload.close_state
    assert_equal "stopped", process_run.lifecycle_state
    assert_equal 0, ToolInvocation.count
  end
end
