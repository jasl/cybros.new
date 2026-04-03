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
          "tool_surface" => [
            {
              "tool_name" => "workspace_write_file",
            },
          ],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ]
    )
    transcript = context.fetch(:workflow_run).conversation_projection.fetch("messages").map { |entry| entry.slice("role", "content") }

    response = ProviderExecution::PrepareProgramRound.call(
      workflow_node: context.fetch(:workflow_node),
      transcript: transcript,
      prior_tool_results: [],
      program_exchange: program_exchange
    )

    request_payload = program_exchange.prepare_round_requests.last

    assert_equal "Round prepared", response.fetch("messages").last.fetch("content")
    assert_equal "workspace_write_file", response.fetch("tool_surface").first.fetch("tool_name")
    assert_equal context.fetch(:conversation).public_id, request_payload.fetch("task").fetch("conversation_id")
    assert_equal context.fetch(:workflow_node).public_id, request_payload.fetch("task").fetch("workflow_node_id")
    assert_equal transcript, request_payload.fetch("conversation_projection").fetch("messages")
    assert_equal context.fetch(:workflow_run).context_imports, request_payload.fetch("conversation_projection").fetch("context_imports")
    assert_equal [], request_payload.fetch("conversation_projection").fetch("prior_tool_results")
    assert_equal context.fetch(:workflow_run).provider_context, request_payload.fetch("provider_context")
    assert_equal "main", request_payload.fetch("capability_projection").fetch("profile_key")
    assert_includes request_payload.fetch("capability_projection").fetch("tool_surface").map { |entry| entry.fetch("tool_name") }, "exec_command"
    assert_equal(
      { "agent_program_version_id" => context.fetch(:deployment).public_id },
      request_payload.fetch("runtime_context").slice("agent_program_version_id")
    )
    assert_equal "prepare-round:#{context.fetch(:workflow_node).public_id}", request_payload.fetch("runtime_context").fetch("logical_work_id")
  end
end
