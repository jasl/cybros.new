require "test_helper"
require "action_cable/test_helper"

class ProviderExecution::ExecuteTurnStepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  class RateLimitedAdapter < SimpleInference::HTTPAdapter
    def call(_env)
      {
        status: 429,
        headers: {
          "content-type" => "application/json",
          "retry-after" => "30",
          "x-request-id" => "rate-limit-request-1",
        },
        body: JSON.generate({ error: { message: "Too many requests" } }),
      }
    end
  end

  class CreditsExhaustedAdapter < SimpleInference::HTTPAdapter
    def call(_env)
      {
        status: 402,
        headers: {
          "content-type" => "application/json",
          "x-request-id" => "credits-request-1",
        },
        body: JSON.generate({ error: { message: "This request requires more credits, or fewer max_tokens." } }),
      }
    end
  end

  class AuthExpiredAdapter < SimpleInference::HTTPAdapter
    def call(_env)
      {
        status: 401,
        headers: { "content-type" => "application/json" },
        body: JSON.generate({ error: { message: "Invalid API key" } }),
      }
    end
  end

  class OverloadedAdapter < SimpleInference::HTTPAdapter
    def call(_env)
      {
        status: 503,
        headers: { "content-type" => "application/json" },
        body: JSON.generate({ error: { message: "upstream overloaded" } }),
      }
    end
  end

  class UnreachableAdapter < SimpleInference::HTTPAdapter
    def call(_env)
      raise SimpleInference::ConnectionError, "Timed out while connecting to upstream provider"
    end
  end

  class ContextOverflowAdapter < SimpleInference::HTTPAdapter
    def call(_env)
      {
        status: 400,
        headers: { "content-type" => "application/json" },
        body: JSON.generate(
          error: {
            code: "context_length_exceeded",
            message: "This model's maximum context length is 128000 tokens, however you requested 145031 tokens.",
          }
        ),
      }
    end
  end

  class StreamingToolCallingAdapter < SimpleInference::HTTPAdapter
    attr_reader :last_request

    def initialize(chunks:, tool_arguments: "{\"messages\":[{\"role\":\"user\",\"content\":\"a\"},{\"role\":\"assistant\",\"content\":\"b\"}],\"budget_hints\":{}}", request_id: "execute-turn-step-tool-stream-request-1", response_id: "chatcmpl-tool-stream-1")
      @chunks = chunks
      @tool_arguments = tool_arguments
      @request_id = request_id
      @response_id = response_id
    end

    def call_stream(env)
      @last_request = env
      sse = +""
      sse << %(data: {"id":"#{@response_id}","choices":[{"delta":{"role":"assistant"},"finish_reason":null}]}\n\n)
      @chunks.each do |chunk|
        sse << %(data: {"id":"#{@response_id}","choices":[{"delta":{"content":"#{chunk}"},"finish_reason":null}]}\n\n)
      end
      sse << %(data: {"id":"#{@response_id}","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-compact-context-1","type":"function","function":{"name":"compact_context","arguments":#{JSON.generate(@tool_arguments)}}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":12,"completion_tokens":6,"total_tokens":18}}\n\n)
      sse << "data: [DONE]\n\n"

      yield sse

      {
        status: 200,
        headers: {
          "content-type" => "text/event-stream",
          "x-request-id" => @request_id,
        },
        body: nil,
      }
    end
  end

  class StreamingToolPlanningAdapter < SimpleInference::HTTPAdapter
    attr_reader :last_request

    def call_stream(env)
      @last_request = env

      chunks = [
        {
          "id" => "chatcmpl-tool-planning-1",
          "object" => "chat.completion.chunk",
          "created" => 1,
          "model" => "mock-model",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "role" => "assistant",
                "content" => "Need to wait for the build. ",
              },
              "finish_reason" => nil,
            },
          ],
        },
        {
          "id" => "chatcmpl-tool-planning-1",
          "object" => "chat.completion.chunk",
          "created" => 1,
          "model" => "mock-model",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "id" => "call_wait_build_1",
                    "type" => "function",
                    "function" => {
                      "name" => "command_run_wait",
                      "arguments" => "{\"command_summary\":\"the test-and-build check in /workspace/game-2048\"",
                    },
                  },
                ],
              },
              "finish_reason" => nil,
            },
          ],
        },
        {
          "id" => "chatcmpl-tool-planning-1",
          "object" => "chat.completion.chunk",
          "created" => 1,
          "model" => "mock-model",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "function" => {
                      "arguments" => "}",
                    },
                  },
                ],
              },
              "finish_reason" => "tool_calls",
            },
          ],
          "usage" => {
            "prompt_tokens" => 12,
            "completion_tokens" => 6,
            "total_tokens" => 18,
          },
        },
      ]

      sse = +""
      chunks.each { |chunk| sse << "data: #{JSON.generate(chunk)}\n\n" }
      sse << "data: [DONE]\n\n"

      yield sse

      {
        status: 200,
        headers: {
          "content-type" => "text/event-stream",
          "x-request-id" => "execute-turn-step-tool-planning-request-1",
        },
        body: nil,
      }
    end
  end

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
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
        messages: turn_step_messages_for(workflow_run),
        adapter: adapter,
        agent_request_exchange: agent_request_exchange
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

  test "broadcasts runtime process events and incremental assistant output deltas for provider execution" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeStreamingChatCompletionsAdapter.new(
      chunks: ["Compaction ", "ready."]
    )
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog,
      tool_contract: default_tool_catalog("exec_command", "compact_context", "subagent_spawn")
    )
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          agent_request_exchange: agent_request_exchange
        )
      end
    end

    assert_equal(
      [
        "runtime.workflow_node.started",
        "runtime.assistant_output.started",
        "runtime.assistant_output.delta",
        "runtime.assistant_output.delta",
        "runtime.assistant_output.completed",
        "runtime.workflow_node.completed",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )

    started_payload = broadcasts.first.fetch("payload")
    first_delta_payload = broadcasts.third.fetch("payload")
    second_delta_payload = broadcasts.fourth.fetch("payload")
    completed_payload = broadcasts.fifth.fetch("payload")

    assert_equal workflow_run.conversation.public_id, broadcasts.first.fetch("conversation_id")
    assert_equal workflow_run.turn.public_id, broadcasts.first.fetch("turn_id")
    assert_equal workflow_run.workflow_nodes.find_by!(node_key: "turn_step").public_id, started_payload.fetch("workflow_node_id")
    assert_equal "Compaction ", first_delta_payload.fetch("delta")
    assert_equal "ready.", second_delta_payload.fetch("delta")
    assert_equal "Compaction ready.", completed_payload.fetch("content")
    assert_equal workflow_run.turn.reload.selected_output_message.public_id, completed_payload.fetch("message_id")

    runtime_projection = ConversationEvent.live_projection(conversation: workflow_run.conversation)
      .select { |event| event.event_kind.start_with?("runtime.workflow_node.") }

    assert_equal 1, runtime_projection.length
    assert_equal "runtime.workflow_node.completed", runtime_projection.first.event_kind
    assert_equal workflow_run.public_id, runtime_projection.first.payload.fetch("workflow_run_id")
    assert_equal workflow_run.workflow_nodes.find_by!(node_key: "turn_step").public_id, runtime_projection.first.payload.fetch("workflow_node_id")
  end

  test "does not emit assistant output runtime events when provider streaming capability is disabled" do
    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog_definition[:providers][:dev][:models]["mock-model"] = test_model_definition(
      display_name: "Mock Model",
      api_model: "mock-model",
      tokenizer_hint: "o200k_base",
      context_window_tokens: 100,
      max_output_tokens: 40,
      request_defaults: {
        temperature: 0.9,
        top_p: 0.95,
        top_k: 20,
        min_p: 0.1,
        presence_penalty: 0.2,
        repetition_penalty: 1.1,
      },
      capabilities: {
        text_output: true,
        tool_calls: true,
        structured_output: true,
        streaming: false,
        conversation_state: false,
        provider_builtin_tools: false,
        image_generation: false,
        multimodal_inputs: {
          image: true,
          audio: false,
          video: false,
          file: true,
        },
      }
    )
    catalog = build_test_provider_catalog_from(catalog_definition)
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-non-streaming-step-1",
        choices: [
          {
            message: { role: "assistant", content: "Short answer." },
            finish_reason: "stop",
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
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          agent_request_exchange: agent_request_exchange
        )
      end
    end

    assert_equal(
      [
        "runtime.workflow_node.started",
        "runtime.workflow_node.completed",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )
    assert_equal "Short answer.", workflow_run.turn.reload.selected_output_message.content
  end

  test "fails speculative assistant output stream when the provider response yields tool continuation" do
    catalog = build_mock_chat_catalog
    adapter = StreamingToolCallingAdapter.new(
      chunks: ["Need ", "compaction."]
    )
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog,
      tool_contract: default_tool_catalog("compact_context")
    )
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          agent_request_exchange: agent_request_exchange
        )
      end
    end

    assert_equal(
      [
        "runtime.workflow_node.started",
        "runtime.assistant_output.started",
        "runtime.assistant_output.delta",
        "runtime.assistant_output.delta",
        "runtime.assistant_tool_call.delta",
        "runtime.assistant_tool_call.completed",
        "runtime.assistant_output.failed",
        "runtime.workflow_node.completed",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )

    failed_payload = broadcasts.fetch(6).fetch("payload")
    assert_equal "tool_continuation", failed_payload.fetch("code")
    assert_match(/superseded by tool continuation/, failed_payload.fetch("message"))
  end

  test "emits assistant tool-call runtime events while streaming a tool continuation" do
    catalog = build_mock_chat_catalog
    adapter = StreamingToolPlanningAdapter.new
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog,
      tool_contract: default_tool_catalog("command_run_wait")
    )
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          agent_request_exchange: agent_request_exchange
        )
      end
    end

    assistant_tool_events = broadcasts.select { |payload| payload.fetch("event_kind").start_with?("runtime.assistant_tool_call.") }

    assert_equal(
      [
        "runtime.assistant_tool_call.delta",
        "runtime.assistant_tool_call.completed",
      ],
      assistant_tool_events.map { |payload| payload.fetch("event_kind") }
    )

    delta_payload = assistant_tool_events.first.fetch("payload")
    completed_payload = assistant_tool_events.second.fetch("payload")

    assert_equal "command_run_wait", delta_payload.fetch("tool_name")
    assert_match(/test-and-build check|workspace\/game-2048/i, delta_payload.fetch("summary"))
    assert_equal "command_run_wait", completed_payload.fetch("tool_name")
    assert_match(/test-and-build check|workspace\/game-2048/i, completed_payload.fetch("summary"))
    refute_includes completed_payload.keys, "arguments"

    runtime_projection = ConversationEvent.live_projection(conversation: workflow_run.conversation)
      .select { |event| event.event_kind.start_with?("runtime.assistant_tool_call.") }

    assert_equal 1, runtime_projection.length
    assert_equal "runtime.assistant_tool_call.completed", runtime_projection.first.event_kind
    assert_equal "command_run_wait", runtime_projection.first.payload.fetch("tool_name")
  end

  test "fails a live assistant output stream when malformed streamed tool arguments raise after deltas begin" do
    catalog = build_mock_chat_catalog
    adapter = StreamingToolCallingAdapter.new(
      chunks: ["Need ", "compaction."],
      tool_arguments: "{\"messages\":"
    )
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog,
      tool_contract: default_tool_catalog("compact_context")
    )
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        error = assert_raises(SimpleInference::DecodeError) do
          ProviderExecution::ExecuteTurnStep.call(
            workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
            messages: turn_step_messages_for(workflow_run),
            adapter: adapter,
            agent_request_exchange: agent_request_exchange
          )
        end

        assert_match(/invalid tool call arguments/, error.message)
      end
    end

    assert_equal(
      [
        "runtime.workflow_node.started",
        "runtime.assistant_output.started",
        "runtime.assistant_output.delta",
        "runtime.assistant_output.delta",
        "runtime.assistant_tool_call.delta",
        "runtime.assistant_tool_call.completed",
        "runtime.assistant_output.failed",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )

    failed_payload = broadcasts.fetch(6).fetch("payload")
    assert_equal "provider_execution_failed", failed_payload.fetch("code")
    assert_match(/invalid tool call arguments/, failed_payload.fetch("message"))
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
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
        messages: turn_step_messages_for(workflow_run),
        adapter: adapter,
        agent_request_exchange: agent_request_exchange
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
                  id: "call-compact-context-1",
                  type: "function",
                  function: {
                    name: "compact_context",
                    arguments: JSON.generate(compact_context_tool_arguments),
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
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new(
      prepared_rounds: [
        {
          "messages" => turn_step_messages_for(workflow_run),
          "visible_tool_names" => ["compact_context"],
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
        agent_request_exchange: agent_request_exchange
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
    assert_equal ["provider_round_1_tool_1"], successor.prior_tool_node_keys
    assert_equal 2, successor.provider_round_index
    assert_equal [], agent_request_exchange.execute_tool_requests

    manifest = workflow_run.workflow_artifacts.find_by!(artifact_kind: "provider_tool_batch_manifest")
    tool_entry = manifest.payload.fetch("stages").sole.fetch("tool_entries").sole

    refute tool_entry.key?("tool_call")
    assert_equal "provider_round_1_tool_1", tool_entry.fetch("tool_node_key")
    assert_equal "call-compact-context-1", tool_entry.fetch("call_id")
    assert_equal "compact_context", tool_entry.fetch("tool_name")
    assert_equal "chat_completions", tool_entry.fetch("provider_format")
  end

  test "materializes a prompt_compaction node and successor turn_step when the round yields compaction" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog,
      request_preparation_contract: {
        "prompt_compaction" => {
          "consultation_mode" => "direct_optional",
          "workflow_execution" => "supported",
          "lifecycle" => "turn_scoped",
        },
      }
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new(
      prepared_rounds: [
        {
          "messages" => [
            { "role" => "system", "content" => "You are a coding agent." },
            { "role" => "user", "content" => "Older context " * 50 },
            { "role" => "user", "content" => "Newest input" },
          ],
          "visible_tool_names" => [],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ],
      prompt_compaction_consults: [
        {
          "status" => "ok",
          "decision" => "compact",
          "diagnostics" => { "reason" => "hard_limit" },
        },
      ]
    )

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: ProviderExecutionTestSupport::FakeQueuedChatCompletionsAdapter.new(response_bodies: []),
        agent_request_exchange: agent_request_exchange,
        request_preparation_exchange: ProviderExecution::RequestPreparationExchange.new(
          agent_definition_version: workflow_run.turn.agent_definition_version,
          agent_request_exchange: agent_request_exchange
        )
      )
    end

    workflow_run.reload
    prompt_compaction_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step_prompt_compaction_1")
    successor = workflow_run.workflow_nodes.find_by!(node_key: "turn_step_prompt_compaction_1_successor")

    assert_equal "completed", workflow_node.reload.lifecycle_state
    assert_equal "queued", prompt_compaction_node.reload.lifecycle_state
    assert_equal "pending", successor.reload.lifecycle_state
    assert_equal 1, successor.provider_round_index
    assert_equal "turn_step_prompt_compaction_1:context", successor.metadata.fetch("prompt_compaction_artifact_key")
    assert_equal "turn_step_prompt_compaction_1", successor.metadata.fetch("prompt_compaction_source_node_key")
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

  test "enters waiting instead of failing when the provider is rate limited" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_node,
          messages: turn_step_messages_for(workflow_run),
          adapter: RateLimitedAdapter.new,
          agent_request_exchange: agent_request_exchange
        )
      end
    end

    assert_equal "active", workflow_run.reload.lifecycle_state
    assert_equal "waiting", workflow_run.wait_state
    assert_equal "external_dependency_blocked", workflow_run.wait_reason_kind
    assert_equal "waiting", workflow_run.turn.reload.lifecycle_state
    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal ["runtime.workflow_node.started", "runtime.workflow_node.waiting"], broadcasts.map { |payload| payload.fetch("event_kind") }
    assert_equal "provider_rate_limited", broadcasts.last.fetch("payload").fetch("failure_kind")

    runtime_projection = ConversationEvent.live_projection(conversation: workflow_run.conversation)
      .select { |event| event.event_kind.start_with?("runtime.workflow_node.") }

    assert_equal 1, runtime_projection.length
    assert_equal "runtime.workflow_node.waiting", runtime_projection.first.event_kind
    assert_equal "provider_rate_limited", runtime_projection.first.payload.fetch("failure_kind")
  end

  test "enters manual waiting instead of failing when provider credits are exhausted" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: CreditsExhaustedAdapter.new,
        agent_request_exchange: agent_request_exchange
      )
    end

    assert_equal "waiting", workflow_run.reload.wait_state
    assert_equal "external_dependency_blocked", workflow_run.wait_reason_kind
    assert_equal "manual", workflow_run.wait_retry_strategy
    assert_equal "provider_credits_exhausted", workflow_run.wait_failure_kind
  end

  test "enters manual waiting instead of failing when provider authentication expires" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: AuthExpiredAdapter.new,
        agent_request_exchange: agent_request_exchange
      )
    end

    assert_equal "waiting", workflow_run.reload.wait_state
    assert_equal "external_dependency_blocked", workflow_run.wait_reason_kind
    assert_equal "manual", workflow_run.wait_retry_strategy
    assert_equal "provider_auth_expired", workflow_run.wait_failure_kind
  end

  test "enters automatic waiting instead of failing when provider is overloaded" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: OverloadedAdapter.new,
        agent_request_exchange: agent_request_exchange
      )
    end

    assert_equal "waiting", workflow_run.reload.wait_state
    assert_equal "external_dependency_blocked", workflow_run.wait_reason_kind
    assert_equal "automatic", workflow_run.wait_retry_strategy
    assert_equal "provider_overloaded", workflow_run.wait_failure_kind
  end

  test "enters automatic waiting instead of failing when provider is unreachable" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: UnreachableAdapter.new,
        agent_request_exchange: agent_request_exchange
      )
    end

    assert_equal "waiting", workflow_run.reload.wait_state
    assert_equal "external_dependency_blocked", workflow_run.wait_reason_kind
    assert_equal "automatic", workflow_run.wait_retry_strategy
    assert_equal "provider_unreachable", workflow_run.wait_failure_kind
  end

  test "enters retryable waiting when the provider returns a blank final response" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-empty-final-1",
        choices: [
          {
            message: { role: "assistant", content: "" },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 12,
          completion_tokens: 0,
          total_tokens: 12,
        },
      }
    )
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_node,
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          agent_request_exchange: agent_request_exchange
        )
      end
    end

    assert_equal "active", workflow_run.reload.lifecycle_state
    assert_equal "waiting", workflow_run.wait_state
    assert_equal "retryable_failure", workflow_run.wait_reason_kind
    assert_equal "invalid_provider_response_contract", workflow_run.wait_failure_kind
    assert_equal "waiting", workflow_run.turn.reload.lifecycle_state
    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_nil workflow_run.turn.reload.selected_output_message
    assert_equal ["runtime.workflow_node.started", "runtime.workflow_node.waiting"], broadcasts.map { |payload| payload.fetch("event_kind") }
    assert_equal "invalid_provider_response_contract", broadcasts.last.fetch("payload").fetch("failure_kind")
  end

  test "persists remediation metadata when the selected input alone exceeds the hard limit" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    long_input = "A" * 800
    workflow_run.turn.selected_input_message.update!(content: long_input)
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new(
      prepared_rounds: [
        {
          "messages" => [
            { "role" => "system", "content" => "You are a coding agent." },
            { "role" => "user", "content" => "Older context" },
            { "role" => "user", "content" => long_input },
          ],
          "visible_tool_names" => [],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ]
    )

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: ProviderExecutionTestSupport::FakeQueuedChatCompletionsAdapter.new(response_bodies: []),
        agent_request_exchange: agent_request_exchange
      )
    end

    wait_payload = workflow_run.reload.wait_reason_payload

    assert_equal "waiting", workflow_run.wait_state
    assert_equal "retryable_failure", workflow_run.wait_reason_kind
    assert_equal "prompt_too_large_for_retry", workflow_run.wait_failure_kind
    assert_equal(
      {
        "tail_input_editable" => true,
        "user_must_send_new_message" => false,
        "failure_scope" => "current_input",
        "current_message_only" => true,
        "selected_input_message_id" => workflow_run.turn.selected_input_message.public_id,
      },
      wait_payload.fetch("remediation")
    )
    assert_equal({}, wait_payload.fetch("degradation", {}))
  end

  test "persists remediation and degradation metadata when a compacted successor still cannot fit" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: { "temperature" => 0.4 },
      catalog: catalog,
      request_preparation_contract: {
        "prompt_compaction" => {
          "consultation_mode" => "direct_optional",
          "workflow_execution" => "supported",
          "lifecycle" => "turn_scoped",
        },
      }
    )
    root_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")

    Workflows::Mutate.call(
      workflow_run: workflow_run,
      nodes: [
        {
          node_key: "turn_step_prompt_compaction_1",
          node_type: "prompt_compaction",
          yielding_node_key: root_node.node_key,
          provider_round_index: 1,
          presentation_policy: "internal_only",
          decision_source: "system",
          metadata: {
            "artifact_key" => "turn_step_prompt_compaction_1:context",
          },
        },
        {
          node_key: "turn_step_prompt_compaction_1_successor",
          node_type: "turn_step",
          yielding_node_key: root_node.node_key,
          provider_round_index: 1,
          presentation_policy: "internal_only",
          decision_source: "system",
          metadata: {
            "prompt_compaction_artifact_key" => "turn_step_prompt_compaction_1:context",
            "prompt_compaction_source_node_key" => "turn_step_prompt_compaction_1",
            "prompt_compaction_includes_prior_tool_results" => true,
            "prompt_compaction_attempt_no" => 1,
            "overflow_recovery_attempt_no" => 1,
          },
        },
      ],
      edges: [
        { from_node_key: root_node.node_key, to_node_key: "turn_step_prompt_compaction_1" },
        { from_node_key: "turn_step_prompt_compaction_1", to_node_key: "turn_step_prompt_compaction_1_successor" },
      ]
    )

    prompt_compaction_node = workflow_run.reload.workflow_nodes.find_by!(node_key: "turn_step_prompt_compaction_1")
    successor = workflow_run.workflow_nodes.find_by!(node_key: "turn_step_prompt_compaction_1_successor")

    WorkflowArtifact.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workflow_node: prompt_compaction_node,
      artifact_key: "turn_step_prompt_compaction_1:context",
      artifact_kind: "prompt_compaction_context",
      storage_mode: "json_document",
      payload: {
        "artifact_kind" => "prompt_compaction_context",
        "messages" => [
          { "role" => "system", "content" => "You are a coding agent." },
          { "role" => "user", "content" => "Compacted earlier context" },
          { "role" => "user", "content" => "Newest input" },
        ],
        "stop_reason" => "hard_limit_after_compaction",
        "failure_scope" => "full_context",
        "selected_input_message_id" => workflow_run.turn.selected_input_message.public_id,
        "source" => "embedded",
        "fallback_used" => true,
        "runtime_failure_code" => "mailbox_timeout",
      }
    )

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: successor,
        messages: ProviderExecution::LoadPromptCompactionContext.call(workflow_node: successor),
        adapter: ContextOverflowAdapter.new,
        agent_request_exchange: ProviderExecutionTestSupport::FakeAgentRequestExchange.new
      )
    end

    wait_payload = workflow_run.reload.wait_reason_payload

    assert_equal "waiting", workflow_run.wait_state
    assert_equal "retryable_failure", workflow_run.wait_reason_kind
    assert_equal "context_window_exceeded_after_compaction", workflow_run.wait_failure_kind
    assert_equal(
      {
        "tail_input_editable" => false,
        "user_must_send_new_message" => true,
        "failure_scope" => "full_context",
        "current_message_only" => false,
        "selected_input_message_id" => workflow_run.turn.selected_input_message.public_id,
      },
      wait_payload.fetch("remediation")
    )
    assert_equal(
      {
        "source" => "embedded",
        "fallback_used" => true,
        "runtime_failure_code" => "mailbox_timeout",
      },
      wait_payload.fetch("degradation")
    )
  end

  test "blocks the step for retry instead of failing when the provider round budget is exceeded" do
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
                    id: "call-compact-context-1",
                    type: "function",
                    function: {
                      name: "compact_context",
                      arguments: JSON.generate(compact_context_tool_arguments),
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
      tool_contract: default_tool_catalog("exec_command", "compact_context", "subagent_spawn")
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new(
      prepared_rounds: [
        {
          "messages" => turn_step_messages_for(workflow_run),
          "visible_tool_names" => ["compact_context"],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ],
      tool_results: {
        "call-compact-context-1" => {
          "status" => "ok",
          "result" => compact_context_tool_result,
          "output_chunks" => [],
          "summary_artifacts" => [],
        },
      }
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_node,
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          agent_request_exchange: agent_request_exchange
        )
      end
    end

    assert_equal "active", workflow_run.reload.lifecycle_state
    assert_equal "waiting", workflow_run.wait_state
    assert_equal "retryable_failure", workflow_run.wait_reason_kind
    assert_equal "waiting", workflow_run.turn.reload.lifecycle_state
    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal(
      [
        "runtime.workflow_node.started",
        "runtime.workflow_node.waiting",
      ],
      broadcasts.map { |payload| payload.fetch("event_kind") }
    )
    assert_equal "provider_round_limit_exceeded", broadcasts.second.fetch("payload").fetch("failure_kind")
  end

  test "returns the workflow node in a waiting state when prepare_round is deferred to an agent receipt" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-should-not-run",
        choices: [
          {
            message: { role: "assistant", content: "should not execute" },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 1,
          completion_tokens: 1,
          total_tokens: 2,
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

    result = nil

    assert_enqueued_with(
      job: Workflows::ResumeBlockedStepJob,
      args: ->(job_args) do
        job_args.first == workflow_run.public_id &&
          job_args.second.is_a?(Hash) &&
          job_args.second[:expected_waiting_since_at_iso8601] == workflow_run.reload.waiting_since_at&.utc&.iso8601(6)
      end
    ) do
      with_stubbed_provider_catalog(catalog) do
        result = ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_node,
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          agent_request_exchange: ProviderExecution::AgentRequestExchange.new(
            agent_definition_version: workflow_run.turn.agent_definition_version,
            timeout: 0.001,
            poll_interval: 0.0,
            sleeper: ->(_duration) { },
          )
        )
      end
    end

    mailbox_item = AgentControlMailboxItem.find_by!(
      workflow_node: workflow_node,
      item_type: "agent_request",
      logical_work_id: "prepare-round:#{workflow_node.public_id}"
    )

    assert_equal workflow_node.public_id, result.public_id
    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal "waiting", workflow_run.reload.wait_state
    assert_equal "agent_request", workflow_run.wait_reason_kind
    assert_equal mailbox_item.public_id, workflow_run.wait_reason_payload.fetch("mailbox_item_id")
  end
end
