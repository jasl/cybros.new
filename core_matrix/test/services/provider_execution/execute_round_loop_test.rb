require "test_helper"

class ProviderExecution::ExecuteRoundLoopTest < ActiveSupport::TestCase
  test "raises a dedicated round limit error when the configured loop budget is exhausted" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeQueuedChatCompletionsAdapter.new(
      response_bodies: [
        {
          id: "chatcmpl-round-1",
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
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      workflow_run = create_mock_turn_step_workflow_run!(
        resolved_config_snapshot: {
          "loop_policy" => {
            "max_rounds" => 1,
          },
        },
        catalog: catalog,
        tool_catalog: default_tool_catalog("exec_command", "compact_context", "subagent_spawn", "calculator")
      )
    end

    transcript = turn_step_messages_for(workflow_run)
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => transcript,
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

    error = assert_raises(ProviderExecution::ExecuteRoundLoop::RoundLimitExceeded) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteRoundLoop.call(
          workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
          transcript: transcript,
          adapter: adapter,
          effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: workflow_run.installation, catalog: catalog),
          program_exchange: program_exchange
        )
      end
    end

    assert_equal 1, error.max_rounds
    assert_equal 2, error.attempted_rounds
    assert_equal transcript.length, error.messages_count
    assert_equal 1, adapter.requests.length
    assert_equal 1, program_exchange.prepare_round_requests.length
  end

  test "ignores legacy loop_settings when loop_policy is absent" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeQueuedChatCompletionsAdapter.new(
      response_bodies: [
        {
          id: "chatcmpl-round-1",
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
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      workflow_run = create_mock_turn_step_workflow_run!(
        resolved_config_snapshot: {},
        catalog: catalog,
        tool_catalog: default_tool_catalog("exec_command", "compact_context", "subagent_spawn", "calculator")
      )
    end

    original_snapshot = workflow_run.execution_snapshot.to_h
    legacy_snapshot = TurnExecutionSnapshot.new(
      original_snapshot.merge(
        "provider_context" => original_snapshot.fetch("provider_context").merge(
          "provider_execution" => original_snapshot.fetch("provider_context").fetch("provider_execution").except("loop_policy").merge(
            "loop_settings" => {
              "max_rounds" => 1,
            }
          )
        )
      )
    )
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_run.define_singleton_method(:execution_snapshot) { legacy_snapshot }
    workflow_node.define_singleton_method(:workflow_run) { workflow_run }
    transcript = turn_step_messages_for(workflow_run)
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => transcript,
          "visible_tool_names" => ["calculator"],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ]
    )

    result = nil

    with_stubbed_provider_catalog(catalog) do
      result = ProviderExecution::ExecuteRoundLoop.call(
        workflow_node: workflow_node,
        transcript: transcript,
        adapter: adapter,
        effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: workflow_run.installation, catalog: catalog),
        program_exchange: program_exchange
      )
    end

    assert result.yielded_tool_batch?
    assert_equal 1, adapter.requests.length
    assert_equal 1, program_exchange.prepare_round_requests.length
  end

  test "exposes visible core matrix tools even when fenix returns no program tools for the round" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-round-core-matrix",
        choices: [
          {
            message: { role: "assistant", content: "No tool call needed." },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 9,
          completion_tokens: 4,
          total_tokens: 13,
        },
      }
    )
    workflow_node = nil
    transcript = nil

    with_stubbed_provider_catalog(catalog) do
      context = build_governed_tool_context!(
        profile_catalog: {
          "main" => {
            "label" => "Main",
            "description" => "Primary interactive profile",
            "allowed_tool_names" => %w[exec_command compact_context subagent_spawn],
          },
        }
      )
      workflow_node = context.fetch(:workflow_node)
      transcript = turn_step_messages_for(context.fetch(:workflow_run))
    end

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteRoundLoop.call(
        workflow_node: workflow_node,
        transcript: transcript,
        adapter: adapter,
        effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: workflow_node.installation, catalog: catalog),
        program_exchange: ProviderExecutionTestSupport::FakeProgramExchange.new(
          prepared_rounds: [
            {
              "messages" => transcript,
              "visible_tool_names" => [],
              "summary_artifacts" => [],
              "trace" => [],
            },
          ]
        )
      )
    end

    request_body = JSON.parse(adapter.last_request.fetch(:body))
    subagent_spawn = request_body.fetch("tools").find { |entry| entry.dig("function", "name") == "subagent_spawn" }

    assert subagent_spawn.present?
    assert_equal "string", subagent_spawn.dig("function", "parameters", "properties", "content", "type")
    assert_equal ["content"], subagent_spawn.dig("function", "parameters", "required")
  end

  test "keeps visible core matrix tools available when the agent program echoes them in prepare_round" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-round-core-matrix-echo",
        choices: [
          {
            message: { role: "assistant", content: "Tools were available." },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 11,
          completion_tokens: 5,
          total_tokens: 16,
        },
      }
    )
    workflow_node = nil
    transcript = nil

    with_stubbed_provider_catalog(catalog) do
      context = build_governed_tool_context!(
        profile_catalog: {
          "main" => {
            "label" => "Main",
            "description" => "Primary interactive profile",
            "allowed_tool_names" => %w[exec_command compact_context subagent_spawn],
          },
        }
      )
      workflow_node = context.fetch(:workflow_node)
      transcript = turn_step_messages_for(context.fetch(:workflow_run))
    end

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteRoundLoop.call(
        workflow_node: workflow_node,
        transcript: transcript,
        adapter: adapter,
        effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: workflow_node.installation, catalog: catalog),
        program_exchange: ProviderExecutionTestSupport::FakeProgramExchange.new(
          prepared_rounds: [
            {
              "messages" => transcript,
              "visible_tool_names" => %w[exec_command subagent_spawn],
              "summary_artifacts" => [],
              "trace" => [],
            },
          ]
        )
      )
    end

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_includes request_body.fetch("tools").map { |entry| entry.dig("function", "name") }, "exec_command"
    assert_includes request_body.fetch("tools").map { |entry| entry.dig("function", "name") }, "subagent_spawn"
  end

  test "returns a graph batch instead of executing tool calls inline" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeQueuedChatCompletionsAdapter.new(
      response_bodies: [
        {
          id: "chatcmpl-round-1",
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
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      workflow_run = create_mock_turn_step_workflow_run!(
        resolved_config_snapshot: {},
        catalog: catalog,
        tool_catalog: default_tool_catalog("exec_command", "compact_context", "subagent_spawn", "calculator")
      )
    end

    transcript = turn_step_messages_for(workflow_run)
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => transcript,
          "visible_tool_names" => ["calculator"],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ]
    )

    result = nil

    with_stubbed_provider_catalog(catalog) do
      result = ProviderExecution::ExecuteRoundLoop.call(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
        transcript: transcript,
        adapter: adapter,
        effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: workflow_run.installation, catalog: catalog),
        program_exchange: program_exchange
      )
    end

    assert result.yielded_tool_batch?
    assert_equal 1, adapter.requests.length
    assert_equal [], program_exchange.execute_program_tool_requests
    assert_equal %w[provider_round_1_tool_1], result.tool_batch_result.fetch("ordered_tool_node_keys")
    assert_equal "provider_round_2", result.tool_batch_result.fetch("successor").fetch("node_key")
  end

  test "loads cumulative prior tool results from predecessor tool nodes" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-round-2",
        choices: [
          {
            message: { role: "assistant", content: "The answer is 4." },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 18,
          completion_tokens: 6,
          total_tokens: 24,
        },
      }
    )
    context = nil

    with_stubbed_provider_catalog(catalog) do
      context = build_governed_tool_context!
    end

    root_node = context.fetch(:workflow_node)
    source_binding = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [calculator_tool_entry]
    ).includes(:tool_definition, :tool_implementation).sole

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_1",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {
            "tool_call" => {
              "call_id" => "call-calculator-1",
              "tool_name" => "calculator",
              "arguments" => { "expression" => "2 + 2" },
              "provider_format" => "chat_completions",
            },
          },
        },
        {
          node_key: "provider_round_2",
          node_type: "turn_step",
          decision_source: "system",
          metadata: {
            "provider_round_index" => 2,
            "prior_tool_node_keys" => ["provider_round_1_tool_1"],
          },
        },
      ],
      edges: [
        { from_node_key: root_node.node_key, to_node_key: "provider_round_1_tool_1" },
        { from_node_key: "provider_round_1_tool_1", to_node_key: "provider_round_2" },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_1")
    successor = root_node.workflow_run.workflow_nodes.find_by!(node_key: "provider_round_2")

    binding = ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      binding_payload: source_binding.binding_payload
    )
    invocation = ToolInvocations::Provision.call(
      tool_binding: binding,
      request_payload: {
        "arguments" => { "expression" => "2 + 2" },
      },
      idempotency_key: "call-calculator-1"
    ).tool_invocation
    ToolInvocations::Complete.call(
      tool_invocation: invocation,
      response_payload: { "value" => 4 }
    )

    transcript = turn_step_messages_for(root_node.workflow_run)
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => transcript,
          "visible_tool_names" => [],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ]
    )

    with_stubbed_provider_catalog(catalog) do
      result = ProviderExecution::ExecuteRoundLoop.call(
        workflow_node: successor,
        transcript: transcript,
        adapter: adapter,
        effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: successor.installation, catalog: catalog),
        program_exchange: program_exchange
      )

      assert result.final?
    end

    request_body = JSON.parse(adapter.last_request.fetch(:body))
    tool_messages = request_body.fetch("messages").last(2)

    assert_equal "assistant", tool_messages.first.fetch("role")
    assert_equal "tool", tool_messages.second.fetch("role")
    assert_equal "calculator", tool_messages.second.fetch("name")
    assert_equal JSON.generate("value" => 4), tool_messages.second.fetch("content")
  end

  private

  def calculator_tool_entry
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
