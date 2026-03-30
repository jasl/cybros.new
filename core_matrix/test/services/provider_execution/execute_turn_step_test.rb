require "test_helper"
require "action_cable/test_helper"

class ProviderExecution::ExecuteTurnStepTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "uses the persisted execution snapshot contract for provider request context" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-direct-step-1",
        choices: [
          {
            message: { role: "assistant", content: "Direct provider result" },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 12,
          completion_tokens: 8,
          total_tokens: 20,
        },
      }
    )
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
        "presence_penalty" => 0.6,
        "sandbox" => "workspace-write",
      },
      catalog: catalog
    )

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
        messages: turn_step_messages_for(workflow_run),
        adapter: adapter
      )
    end

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal "mock-model", request_body.fetch("model")
    assert_equal 0.4, request_body.fetch("temperature")
    assert_equal 0.95, request_body.fetch("top_p")
    assert_equal 20, request_body.fetch("top_k")
    assert_equal 0.1, request_body.fetch("min_p")
    assert_equal 0.6, request_body.fetch("presence_penalty")
    assert_equal 1.1, request_body.fetch("repetition_penalty")
    assert_equal 40, request_body.fetch("max_tokens")
    refute request_body.key?("sandbox")
    assert_equal "Direct provider result", workflow_run.turn.reload.selected_output_message.content
  end

  test "broadcasts runtime process events and a temporary assistant output stream for provider execution" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeStreamingChatCompletionsAdapter.new(
      chunks: ["The calculator ", "returned 4."]
    )
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter
        )
      end
    end

    assert_equal(
      [
        "runtime.workflow_node.started",
        "runtime.assistant_output.started",
        "runtime.assistant_output.delta",
        "runtime.assistant_output.completed",
        "runtime.workflow_node.completed",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )

    started_payload = broadcasts.first.fetch("payload")
    delta_payload = broadcasts.third.fetch("payload")
    completed_payload = broadcasts.fourth.fetch("payload")

    assert_equal workflow_run.conversation.public_id, broadcasts.first.fetch("conversation_id")
    assert_equal workflow_run.turn.public_id, broadcasts.first.fetch("turn_id")
    assert_equal workflow_run.workflow_nodes.find_by!(node_key: "turn_step").public_id, started_payload.fetch("workflow_node_id")
    assert_equal "The calculator returned 4.", delta_payload.fetch("delta")
    assert_equal "The calculator returned 4.", completed_payload.fetch("content")
    assert_equal workflow_run.turn.reload.selected_output_message.public_id, completed_payload.fetch("message_id")
  end

  test "rejects a turn_step that was already claimed running before dispatch" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-direct-step-running",
        choices: [
          {
            message: { role: "assistant", content: "Should not dispatch" },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 12,
          completion_tokens: 8,
          total_tokens: 20,
        },
      }
    )
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(
      lifecycle_state: "running",
      started_at: Time.current,
      finished_at: nil
    )

    assert_raises(ProviderExecution::ExecuteTurnStep::StaleExecutionError) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_node,
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter
        )
      end
    end

    assert_nil adapter.last_request
    assert_equal 0, WorkflowNodeEvent.where(workflow_node: workflow_node, event_kind: "status").count
  end
end
