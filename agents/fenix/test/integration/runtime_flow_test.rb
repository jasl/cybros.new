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

  test "shared core matrix execution assignment fixture preserves the real model and visible tool contract" do
    mailbox_item = shared_contract_fixture("core_matrix_fenix_execution_assignment_v1")

    context = Fenix::Context::BuildExecutionContext.call(mailbox_item: mailbox_item)
    prepared = Fenix::Hooks::PrepareTurn.call(context: context)

    assert_equal "gpt-5.4", context.dig("model_context", "model_ref")
    assert_equal "gpt-5.4", context.dig("model_context", "api_model")
    assert_equal 900_000, context.dig("budget_hints", "advisory_hints", "recommended_compaction_threshold")
    assert_equal "researcher", context.dig("agent_context", "profile")
    assert_equal true, context.dig("agent_context", "is_subagent")
    assert_equal %w[subagent_send subagent_wait subagent_close subagent_list compact_context estimate_messages estimate_tokens calculator],
      context.dig("agent_context", "allowed_tool_names")
    assert_equal "gpt-5.4", prepared.fetch("likely_model")
    assert_equal "researcher", prepared.dig("trace", "profile")
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

  test "runtime execution endpoint rejects masked direct tool invocation from the frozen visible tool set" do
    post "/runtime/executions",
      params: runtime_assignment_payload(
        mode: "deterministic_tool",
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens]
        )
      ),
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)

    assert_equal %w[execution_started execution_fail],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal "failed", body.fetch("status")
    assert_equal "runtime_error", body.fetch("error").fetch("failure_kind")
    assert_match(/calculator/, body.fetch("error").fetch("last_error_summary"))
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
