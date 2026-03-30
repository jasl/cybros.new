require "test_helper"

class RuntimeFlowTest < ActiveSupport::TestCase
  test "mailbox worker enqueues work and exposes terminal reports through the runtime execution record" do
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

  test "mailbox worker keeps one shared flow for subagent assignments" do
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

  test "mailbox worker persists failed executions for masked direct tool invocation" do
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

  test "mailbox worker supports exec_command through the command run contract" do
    body = run_runtime_execution(
      runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "exec_command",
          "command_line" => "printf 'hello\\n'",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
        )
      )
    )

    completed_invocation = body.fetch("reports").last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", body.fetch("status")
    assert_equal "Command exited with status 0 after streaming output.", body.fetch("output")
    assert_equal "exec_command", completed_invocation.fetch("tool_name")
    assert_equal 0, completed_invocation.dig("response_payload", "exit_status")
    assert_equal true, completed_invocation.dig("response_payload", "output_streamed")
  end

  test "mailbox worker supports process_exec through the process manager contract" do
    body = run_runtime_execution(
      runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "process_exec",
          "command_line" => "trap 'exit 0' TERM; while :; do sleep 1; done",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["process_exec"]
        )
      )
    )

    assert_equal "completed", body.fetch("status")
    assert_match(/Background service started as process run /, body.fetch("output"))
    refute body.fetch("reports").last.fetch("terminal_payload").key?("tool_invocations")
  end

  test "mailbox worker persists runtime failures through handle_error" do
    body = run_runtime_execution(runtime_assignment_payload(mode: "raise_error"))

    assert_equal %w[execution_started execution_fail],
      body.fetch("reports").map { |report| report.fetch("method_id") }
    assert_equal ["agent"], body.fetch("reports").map { |report| report.fetch("runtime_plane") }.uniq
    assert_equal "failed", body.fetch("status")
    assert_equal "runtime_error", body.fetch("error").fetch("failure_kind")
  end

  test "mailbox worker persists unsupported runtime-plane failures" do
    body = run_runtime_execution(runtime_assignment_payload(runtime_plane: "environment"))

    assert_equal "failed", body.fetch("status")
    assert_equal "unsupported_runtime_plane", body.fetch("error").fetch("failure_kind")
  end

  test "mailbox worker is idempotent for duplicate assignment delivery" do
    payload = runtime_assignment_payload(mode: "deterministic_tool")
    first_execution = nil
    second_execution = nil

    assert_enqueued_jobs 1 do
      first_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: payload)
      second_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: payload)
    end

    assert_equal first_execution.id, second_execution.id

    perform_enqueued_jobs

    assert_equal "completed", first_execution.reload.status
  end

  private

  def run_runtime_execution(payload)
    runtime_execution = nil

    assert_enqueued_jobs 1 do
      runtime_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: payload)
      assert_equal "queued", runtime_execution.status
    end

    perform_enqueued_jobs

    serialize_runtime_execution(runtime_execution.reload)
  end

  def serialize_runtime_execution(runtime_execution)
    {
      "execution_id" => runtime_execution.execution_id,
      "status" => runtime_execution.status,
      "output" => runtime_execution.output_payload,
      "error" => runtime_execution.error_payload,
      "reports" => runtime_execution.reports,
      "trace" => runtime_execution.trace,
      "mailbox_item_id" => runtime_execution.mailbox_item_id,
      "logical_work_id" => runtime_execution.logical_work_id,
      "attempt_no" => runtime_execution.attempt_no,
      "runtime_plane" => runtime_execution.runtime_plane,
      "started_at" => runtime_execution.started_at,
      "finished_at" => runtime_execution.finished_at,
    }.compact
  end
end
