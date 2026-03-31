require "test_helper"

class ProviderExecution::PrepareProgramRoundTest < ActiveSupport::TestCase
  test "builds the fenix prepare_round payload from workflow execution state" do
    context = build_governed_tool_context!
    context.fetch(:deployment).update!(
      endpoint_metadata: context.fetch(:deployment).endpoint_metadata.merge(
        "prepare_round_path" => "/runtime/rounds/prepare",
        "execute_program_tool_path" => "/runtime/program_tools/execute"
      )
    )
    transport = ProviderExecutionTestSupport::FakeJsonTransport.new(
      response: ProviderExecutionTestSupport::FakeHttpResponse.new(
        code: "200",
        body: JSON.generate(
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
          "likely_model" => "gpt-5.4"
        ),
        headers: {}
      )
    )
    client = ProviderExecution::FenixProgramClient.new(
      agent_deployment: context.fetch(:deployment),
      transport: transport
    )
    transcript = context.fetch(:workflow_run).context_messages.map { |entry| entry.slice("role", "content") }

    response = ProviderExecution::PrepareProgramRound.call(
      workflow_node: context.fetch(:workflow_node),
      transcript: transcript,
      prior_tool_results: [],
      client: client
    )

    request_body = JSON.parse(transport.last_body)

    assert_equal "Round prepared", response.fetch("messages").last.fetch("content")
    assert_equal "workspace_write_file", response.fetch("program_tools").first.fetch("tool_name")
    assert_equal context.fetch(:conversation).public_id, request_body.fetch("conversation_id")
    assert_equal context.fetch(:workflow_node).public_id, request_body.fetch("workflow_node_id")
    assert_equal transcript, request_body.fetch("transcript")
    assert_equal context.fetch(:workflow_run).context_imports, request_body.fetch("context_imports")
    assert_equal context.fetch(:workflow_run).budget_hints, request_body.fetch("budget_hints")
    assert_equal context.fetch(:workflow_run).provider_execution, request_body.fetch("provider_execution")
    assert_equal context.fetch(:workflow_run).model_context, request_body.fetch("model_context")
    assert_equal context.fetch(:workflow_run).execution_snapshot.agent_context, request_body.fetch("agent_context")
  end
end
