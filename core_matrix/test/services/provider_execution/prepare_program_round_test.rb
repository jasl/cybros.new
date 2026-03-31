require "test_helper"

class ProviderExecution::PrepareProgramRoundTest < ActiveSupport::TestCase
  test "builds the agent program prepare_round payload from workflow execution state" do
    context = build_governed_tool_context!
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => [
            { "role" => "assistant", "content" => "Round prepared" },
          ],
          "program_tools" => [
            {
              "tool_name" => "workspace_write_file",
              "tool_kind" => "effect_intent",
              "implementation_source" => "agent",
              "implementation_ref" => "fenix/runtime/workspace_write_file",
              "input_schema" => { "type" => "object", "properties" => {} },
              "result_schema" => { "type" => "object", "properties" => {} },
              "streaming_support" => false,
              "idempotency_policy" => "best_effort",
            },
          ],
          "likely_model" => "gpt-5.4",
        },
      ]
    )
    transcript = context.fetch(:workflow_run).context_messages.map { |entry| entry.slice("role", "content") }

    response = ProviderExecution::PrepareProgramRound.call(
      workflow_node: context.fetch(:workflow_node),
      transcript: transcript,
      prior_tool_results: [],
      program_exchange: program_exchange
    )

    request_payload = program_exchange.prepare_round_requests.last

    assert_equal "Round prepared", response.fetch("messages").last.fetch("content")
    assert_equal "workspace_write_file", response.fetch("program_tools").first.fetch("tool_name")
    assert_equal context.fetch(:conversation).public_id, request_payload.fetch("conversation_id")
    assert_equal context.fetch(:workflow_node).public_id, request_payload.fetch("workflow_node_id")
    assert_equal transcript, request_payload.fetch("transcript")
    assert_equal context.fetch(:workflow_run).context_imports, request_payload.fetch("context_imports")
    assert_equal context.fetch(:workflow_run).budget_hints, request_payload.fetch("budget_hints")
    assert_equal context.fetch(:workflow_run).provider_execution, request_payload.fetch("provider_execution")
    assert_equal context.fetch(:workflow_run).model_context, request_payload.fetch("model_context")
    assert_equal context.fetch(:workflow_run).execution_snapshot.agent_context, request_payload.fetch("agent_context")
  end
end
