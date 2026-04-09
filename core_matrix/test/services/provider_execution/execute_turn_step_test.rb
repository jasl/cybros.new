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

    runtime_projection = ConversationEvent.live_projection(conversation: workflow_run.conversation)
      .select { |event| event.event_kind.start_with?("runtime.workflow_node.") }

    assert_equal 1, runtime_projection.length
    assert_equal "runtime.workflow_node.completed", runtime_projection.first.event_kind
    assert_equal workflow_run.public_id, runtime_projection.first.payload.fetch("workflow_run_id")
    assert_equal workflow_run.workflow_nodes.find_by!(node_key: "turn_step").public_id, runtime_projection.first.payload.fetch("workflow_node_id")
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
          "visible_tool_names" => ["calculator"],
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
    assert_equal ["provider_round_1_tool_1"], successor.prior_tool_node_keys
    assert_equal 2, successor.provider_round_index
    assert_equal [], program_exchange.execute_program_tool_requests

    manifest = workflow_run.workflow_artifacts.find_by!(artifact_kind: "provider_tool_batch_manifest")
    tool_entry = manifest.payload.fetch("stages").sole.fetch("tool_entries").sole

    refute tool_entry.key?("tool_call")
    assert_equal "provider_round_1_tool_1", tool_entry.fetch("tool_node_key")
    assert_equal "call-calculator-1", tool_entry.fetch("call_id")
    assert_equal "calculator", tool_entry.fetch("tool_name")
    assert_equal "chat_completions", tool_entry.fetch("provider_format")
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
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_node,
          messages: turn_step_messages_for(workflow_run),
          adapter: RateLimitedAdapter.new,
          program_exchange: program_exchange
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
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: CreditsExhaustedAdapter.new,
        program_exchange: program_exchange
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
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: AuthExpiredAdapter.new,
        program_exchange: program_exchange
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
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: OverloadedAdapter.new,
        program_exchange: program_exchange
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
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_node,
        messages: turn_step_messages_for(workflow_run),
        adapter: UnreachableAdapter.new,
        program_exchange: program_exchange
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
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new
    stream_name = ConversationRuntime::StreamName.for_conversation(workflow_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_node,
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          program_exchange: program_exchange
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
          "visible_tool_names" => ["calculator"],
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
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_node,
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          program_exchange: program_exchange
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

  test "returns the workflow node in a waiting state when prepare_round is deferred to an agent program receipt" do
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

    assert_enqueued_with(job: Workflows::ResumeBlockedStepJob, args: [workflow_run.public_id]) do
      with_stubbed_provider_catalog(catalog) do
        result = ProviderExecution::ExecuteTurnStep.call(
          workflow_node: workflow_node,
          messages: turn_step_messages_for(workflow_run),
          adapter: adapter,
          program_exchange: ProviderExecution::ProgramMailboxExchange.new(
            agent_program_version: workflow_run.turn.agent_program_version,
            timeout: 0.001,
            poll_interval: 0.0,
            sleeper: ->(_duration) { },
          )
        )
      end
    end

    mailbox_item = AgentControlMailboxItem.find_by!(
      workflow_node: workflow_node,
      item_type: "agent_program_request",
      logical_work_id: "prepare-round:#{workflow_node.public_id}"
    )

    assert_equal workflow_node.public_id, result.public_id
    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal "waiting", workflow_run.reload.wait_state
    assert_equal "agent_program_request", workflow_run.wait_reason_kind
    assert_equal mailbox_item.public_id, workflow_run.wait_reason_payload.fetch("mailbox_item_id")
  end

  private

  def round_budget_calculator_tool_entry
    {
      "tool_name" => "calculator",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/agent/calculator",
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
