require "test_helper"

class ProviderExecution::PrepareProgramRoundTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "builds the agent program prepare_round payload from workflow execution state" do
    context = build_governed_tool_context!
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => [
            { "role" => "assistant", "content" => "Round prepared" },
          ],
          "visible_tool_names" => ["workspace_write_file"],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ]
    )
    transcript = context.fetch(:workflow_run).conversation_projection.fetch("messages").map { |entry| entry.slice("role", "content") }

    response = ProviderExecution::PrepareProgramRound.call(
      workflow_node: context.fetch(:workflow_node),
      transcript: transcript,
      program_exchange: program_exchange
    )

    request_payload = program_exchange.prepare_round_requests.last

    assert_equal "Round prepared", response.fetch("messages").last.fetch("content")
    assert_equal ["workspace_write_file"], response.fetch("visible_tool_names")
    assert_equal context.fetch(:conversation).public_id, request_payload.fetch("task").fetch("conversation_id")
    assert_equal context.fetch(:workflow_node).public_id, request_payload.fetch("task").fetch("workflow_node_id")
    assert_equal transcript, request_payload.fetch("round_context").fetch("messages")
    assert_equal context.fetch(:workflow_run).context_imports, request_payload.fetch("round_context").fetch("context_imports")
    assert_equal context.fetch(:workflow_run).provider_context, request_payload.fetch("provider_context")
    assert_equal "main", request_payload.fetch("agent_context").fetch("profile")
    assert_includes request_payload.fetch("agent_context").fetch("allowed_tool_names"), "exec_command"
    assert_equal(
      {
        "agent_program_version_id" => context.fetch(:deployment).public_id,
        "agent_program_id" => context.fetch(:agent_program).public_id,
        "user_id" => context.fetch(:user).public_id,
      },
      request_payload.fetch("runtime_context").slice("agent_program_version_id", "agent_program_id", "user_id")
    )
    assert_equal "prepare-round:#{context.fetch(:workflow_node).public_id}", request_payload.fetch("runtime_context").fetch("logical_work_id")
  end

  test "includes work_context_view in the prepare_round payload" do
    context = build_governed_tool_context!
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => [
            { "role" => "assistant", "content" => "Round prepared" },
          ],
          "visible_tool_names" => ["workspace_write_file"],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ]
    )
    transcript = [
      { "role" => "user", "content" => "Prepare the work context" },
    ]

    ProviderExecution::PrepareProgramRound.call(
      workflow_node: context.fetch(:workflow_node),
      transcript: transcript,
      program_exchange: program_exchange
    )

    request_payload = program_exchange.prepare_round_requests.last

    assert_equal(
      ProviderExecution::BuildWorkContextView.call(workflow_node: context.fetch(:workflow_node)),
      request_payload.fetch("round_context").fetch("work_context_view")
    )
  end

  test "carries delivered supervisor guidance through round_context work_context_view" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => [
            { "role" => "assistant", "content" => "Round prepared" },
          ],
          "visible_tool_names" => ["workspace_write_file"],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ]
    )
    transcript = [
      { "role" => "user", "content" => "Please prepare the next round." },
    ]

    ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "send_guidance_to_active_agent",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "completed",
      request_payload: { "content" => "Summarize the blocker before writing code." },
      result_payload: {
        "response_payload" => {
          "control_outcome" => {
            "outcome_kind" => "guidance_acknowledged",
          },
        },
      },
      completed_at: Time.current
    )

    ProviderExecution::PrepareProgramRound.call(
      workflow_node: fixture.fetch(:workflow_node),
      transcript: transcript,
      program_exchange: program_exchange
    )

    request_payload = program_exchange.prepare_round_requests.last

    assert_equal "conversation", request_payload.dig("round_context", "work_context_view", "supervisor_guidance", "guidance_scope")
    assert_equal "Summarize the blocker before writing code.",
      request_payload.dig("round_context", "work_context_view", "supervisor_guidance", "latest_guidance", "content")
  end
end
