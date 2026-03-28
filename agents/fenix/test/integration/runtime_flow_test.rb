require "test_helper"

class RuntimeFlowTest < ActionDispatch::IntegrationTest
  test "runtime execution endpoint returns start progress and terminal reports" do
    post "/runtime/executions",
      params: runtime_assignment_payload(mode: "deterministic_tool"),
      as: :json

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal %w[execution_started execution_progress execution_complete],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal ["agent"], body.fetch("reports").map { |report| report.fetch("runtime_plane") }.uniq
    assert_equal "completed", body.fetch("status")
    assert_equal "The calculator returned 4.", body.fetch("output")
    assert_equal "main", body.fetch("trace").first.fetch("profile")
    assert_equal false, body.fetch("trace").first.fetch("is_subagent")
  end

  test "execution payload parsing exposes agent context and prepare_turn sees profile and allowed tool names" do
    mailbox_item = runtime_assignment_payload(
      agent_context: {
        "profile" => "researcher",
        "is_subagent" => true,
        "subagent_session_id" => "subagent-session-1",
        "parent_subagent_session_id" => "subagent-session-0",
        "subagent_depth" => 1,
        "allowed_tool_names" => %w[compact_context calculator subagent_send subagent_wait subagent_close subagent_list],
      }
    )

    context = Fenix::Context::BuildExecutionContext.call(mailbox_item: mailbox_item)
    prepared = Fenix::Hooks::PrepareTurn.call(context: context)

    assert_equal "researcher", context.dig("agent_context", "profile")
    assert_equal true, context.dig("agent_context", "is_subagent")
    assert_equal 1, context.dig("agent_context", "subagent_depth")
    assert_equal %w[compact_context calculator subagent_send subagent_wait subagent_close subagent_list], context.dig("agent_context", "allowed_tool_names")
    assert_equal "researcher", prepared.dig("trace", "profile")
    assert_equal true, prepared.dig("trace", "is_subagent")
    assert_equal %w[compact_context calculator subagent_send subagent_wait subagent_close subagent_list], prepared.dig("trace", "allowed_tool_names")
    assert_equal "gpt-4.1-mini", prepared.fetch("likely_model")
  end

  test "runtime execution endpoint keeps one shared flow for subagent assignments" do
    post "/runtime/executions",
      params: runtime_assignment_payload(
        mode: "deterministic_tool",
        agent_context: {
          "profile" => "researcher",
          "is_subagent" => true,
          "subagent_session_id" => "subagent-session-1",
          "parent_subagent_session_id" => "subagent-session-0",
          "subagent_depth" => 1,
          "allowed_tool_names" => %w[compact_context calculator subagent_send subagent_wait subagent_close subagent_list],
        }
      ),
      as: :json

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal %w[execution_started execution_progress execution_complete],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal "completed", body.fetch("status")
    assert_equal "The calculator returned 4.", body.fetch("output")
    assert_equal "researcher", body.fetch("trace").first.fetch("profile")
    assert_equal true, body.fetch("trace").first.fetch("is_subagent")
  end

  test "runtime execution endpoint reports failures through handle_error" do
    post "/runtime/executions",
      params: runtime_assignment_payload(mode: "raise_error"),
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)

    assert_equal %w[execution_started execution_fail],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal ["agent"], body.fetch("reports").map { |report| report.fetch("runtime_plane") }.uniq
    assert_equal "failed", body.fetch("status")
    assert_equal "runtime_error", body.fetch("error").fetch("failure_kind")
  end

  test "runtime execution endpoint rejects non-agent runtime planes" do
    post "/runtime/executions",
      params: runtime_assignment_payload(runtime_plane: "environment"),
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)

    assert_equal "failed", body.fetch("status")
    assert_equal "unsupported_runtime_plane", body.fetch("error").fetch("failure_kind")
  end
end
