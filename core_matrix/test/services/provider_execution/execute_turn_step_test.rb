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
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
        messages: turn_step_messages_for(workflow_run),
        adapter: adapter,
        program_exchange: program_exchange
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
      catalog: catalog,
      tool_catalog: default_tool_catalog("exec_command", "compact_context", "subagent_spawn", "calculator")
    )
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          program_exchange: program_exchange
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

  test "persists normalized responses-api output text instead of raw provider_result content" do
    catalog = build_mock_responses_catalog
    adapter = ProviderExecutionTestSupport::FakeResponsesAdapter.new(
      response_body: {
        "output" => [
          {
            "type" => "message",
            "content" => [
              {
                "type" => "output_text",
                "text" => "Responses provider result",
              },
            ],
          },
        ],
        "usage" => {
          "input_tokens" => 9,
          "output_tokens" => 5,
          "total_tokens" => 14,
        },
      }
    )
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
        messages: turn_step_messages_for(workflow_run),
        adapter: adapter,
        program_exchange: program_exchange
      )
    end

    assert_equal "Responses provider result", workflow_run.turn.reload.selected_output_message.content
  end

  test "materializes tool calls as workflow nodes and leaves the turn active for graph re-entry" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-tool-batch-1",
        choices: [
          {
            message: {
              role: "assistant",
              tool_calls: [
                {
                  id: "call-calculator-1",
                  type: "function",
                  function: {
                    name: "calculator",
                    arguments: JSON.generate(expression: "2 + 2"),
                  },
                },
              ],
            },
            finish_reason: "tool_calls",
          },
        ],
        usage: {
          prompt_tokens: 12,
          completion_tokens: 4,
          total_tokens: 16,
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
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => turn_step_messages_for(workflow_run),
          "tool_surface" => [round_budget_calculator_tool_entry],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ]
    )

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: adapter,
        program_exchange: program_exchange
      )
    end

    workflow_run.reload
    tool_node = workflow_run.workflow_nodes.find_by!(node_key: "provider_round_1_tool_1")
    join_node = workflow_run.workflow_nodes.find_by!(node_key: "provider_round_1_join_1")
    successor = workflow_run.workflow_nodes.find_by!(node_key: "provider_round_2")

    assert workflow_run.active?
    assert workflow_run.turn.reload.active?
    assert_equal "completed", workflow_node.reload.lifecycle_state
    assert_equal "queued", tool_node.reload.lifecycle_state
    assert_equal "pending", join_node.reload.lifecycle_state
    assert_equal "pending", successor.reload.lifecycle_state
    assert_equal ["provider_round_1_tool_1"], successor.metadata.fetch("prior_tool_node_keys")
    assert_equal [], program_exchange.execute_program_tool_requests
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

  test "persists a failed turn when the provider round budget is exceeded" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeQueuedChatCompletionsAdapter.new(
      response_bodies: [
        {
          id: "chatcmpl-round-budget-1",
          choices: [
            {
              message: {
                role: "assistant",
                tool_calls: [
                  {
                    id: "call-calculator-1",
                    type: "function",
                    function: {
                      name: "calculator",
                      arguments: JSON.generate(expression: "2 + 2"),
                    },
                  },
                ],
              },
              finish_reason: "tool_calls",
            },
          ],
          usage: {
            prompt_tokens: 12,
            completion_tokens: 4,
            total_tokens: 16,
          },
        },
      ]
    )
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
        "loop_policy" => {
          "max_rounds" => 1,
        },
      },
      catalog: catalog,
      tool_catalog: default_tool_catalog("exec_command", "compact_context", "subagent_spawn", "calculator")
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => turn_step_messages_for(workflow_run),
          "tool_surface" => [round_budget_calculator_tool_entry],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ],
      program_tool_results: {
        "call-calculator-1" => {
          "status" => "ok",
          "result" => { "value" => 4 },
          "output_chunks" => [],
          "summary_artifacts" => [],
        },
      }
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      error = assert_raises(ProviderExecution::ExecuteRoundLoop::RoundLimitExceeded) do
        with_stubbed_provider_catalog(catalog) do
          ProviderExecution::ExecuteTurnStep.call(
            workflow_node: workflow_node,
            messages: turn_step_messages_for(workflow_run),
            adapter: adapter,
            program_exchange: program_exchange
          )
        end
      end

      assert_equal "provider round loop exceeded 1 rounds", error.message
    end

    assert_equal "failed", workflow_run.reload.lifecycle_state
    assert_equal "failed", workflow_run.turn.reload.lifecycle_state
    assert_equal "failed", workflow_node.reload.lifecycle_state
    assert_equal(
      [
        "runtime.workflow_node.started",
        "runtime.workflow_node.failed",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )
    assert_equal "provider_round_limit_exceeded", broadcasts.second.fetch("payload").fetch("code")
  end

  private

  def round_budget_calculator_tool_entry
    {
      "tool_name" => "calculator",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/runtime/calculator",
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "expression" => { "type" => "string" },
        },
      },
      "result_schema" => {
        "type" => "object",
        "properties" => {
          "value" => { "type" => "integer" },
        },
      },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
  end
end
