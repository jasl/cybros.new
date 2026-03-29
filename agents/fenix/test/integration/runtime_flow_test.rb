require "test_helper"

class RuntimeFlowTest < ActionDispatch::IntegrationTest
  test "runtime execution endpoint enqueues work and exposes terminal reports through the execution resource" do
    body = run_runtime_execution(runtime_assignment_payload(mode: "deterministic_tool"))

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

    assert_equal mailbox_item.fetch("protocol_message_id"), context.fetch("protocol_message_id")
    assert_equal "turn_step", context.fetch("kind")
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

    assert_equal "kernel-assignment-message-id", context.fetch("protocol_message_id")
    assert_equal "subagent_step", context.fetch("kind")
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
    body = run_runtime_execution(
      runtime_assignment_payload(
        mode: "deterministic_tool",
        agent_context: {
          "profile" => "researcher",
          "is_subagent" => true,
          "subagent_session_id" => "subagent-session-1",
          "parent_subagent_session_id" => "subagent-session-0",
          "subagent_depth" => 1,
          "allowed_tool_names" => %w[compact_context calculator subagent_send subagent_wait subagent_close subagent_list],
        }
      )
    )

    assert_equal %w[execution_started execution_progress execution_complete],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal "completed", body.fetch("status")
    assert_equal "The calculator returned 4.", body.fetch("output")
    assert_equal "researcher", body.fetch("trace").first.fetch("profile")
    assert_equal true, body.fetch("trace").first.fetch("is_subagent")
  end

  test "runtime execution endpoint persists failed executions for masked direct tool invocation" do
    body = run_runtime_execution(
      runtime_assignment_payload(
        mode: "deterministic_tool",
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens]
        )
      )
    )

    assert_equal %w[execution_started execution_fail],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal "failed", body.fetch("status")
    assert_equal "runtime_error", body.fetch("error").fetch("failure_kind")
    assert_match(/calculator/, body.fetch("error").fetch("last_error_summary"))
  end

  test "runtime execution endpoint persists runtime failures through handle_error" do
    body = run_runtime_execution(runtime_assignment_payload(mode: "raise_error"))

    assert_equal %w[execution_started execution_fail],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal ["agent"], body.fetch("reports").map { |report| report.fetch("runtime_plane") }.uniq
    assert_equal "failed", body.fetch("status")
    assert_equal "runtime_error", body.fetch("error").fetch("failure_kind")
  end

  test "runtime execution endpoint persists unsupported runtime-plane failures" do
    body = run_runtime_execution(runtime_assignment_payload(runtime_plane: "environment"))

    assert_equal "failed", body.fetch("status")
    assert_equal "unsupported_runtime_plane", body.fetch("error").fetch("failure_kind")
  end

  test "runtime execution endpoint is idempotent for duplicate assignment delivery" do
    payload = runtime_assignment_payload(mode: "deterministic_tool")
    first_execution_id = nil
    second_execution_id = nil

    assert_enqueued_jobs 1 do
      post "/runtime/executions", params: payload, as: :json
      assert_response :accepted
      first_execution_id = JSON.parse(response.body).fetch("execution_id")

      post "/runtime/executions", params: payload, as: :json
      assert_response :accepted
      second_execution_id = JSON.parse(response.body).fetch("execution_id")
    end

    assert_equal first_execution_id, second_execution_id

    perform_enqueued_jobs

    get "/runtime/executions/#{first_execution_id}"
    assert_response :success
    assert_equal "completed", JSON.parse(response.body).fetch("status")
  end

  private

  def run_runtime_execution(payload)
    execution_id = nil

    assert_enqueued_jobs 1 do
      post "/runtime/executions", params: payload, as: :json
      assert_response :accepted

      queued_body = JSON.parse(response.body)
      assert_equal "queued", queued_body.fetch("status")
      execution_id = queued_body.fetch("execution_id")
    end

    perform_enqueued_jobs

    get "/runtime/executions/#{execution_id}"
    assert_response :success

    JSON.parse(response.body)
  end
end
