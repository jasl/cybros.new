require "test_helper"
require "action_cable/test_helper"

class AgentApiProcessRuntimeTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  test "process_output streams stdout chunks without persisting them" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      post "/agent_api/control/report",
        params: {
          method_id: "process_output",
          protocol_message_id: "process-output-#{next_test_sequence}",
          resource_type: "ProcessRun",
          resource_id: process_run.public_id,
          output_chunks: [
            { "stream" => "stdout", "text" => "hello from process\n" },
          ],
        },
        headers: agent_api_headers(context[:machine_credential]),
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
end
