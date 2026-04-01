require "test_helper"

class RuntimeProgramContractTest < ActiveSupport::TestCase
  test "prepare_round mailbox work emits the frozen completed report shape" do
    result = run_runtime_execution(shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item"))

    report = result.fetch("reports").last

    assert_equal shared_contract_fixture("fenix_prepare_round_report"), normalize_prepare_round_report(report)
  end

  test "execute_program_tool mailbox work emits the frozen completed report shape" do
    result = run_runtime_execution(shared_contract_fixture("core_matrix_fenix_execute_program_tool_mailbox_item"))

    report = result.fetch("reports").last

    assert_equal shared_contract_fixture("fenix_execute_program_tool_report"), normalize_program_tool_report(report)
  end

  test "execute_program_tool mailbox work rejects tools outside the visible program surface" do
    payload = shared_contract_fixture("core_matrix_fenix_execute_program_tool_mailbox_item")
    payload["payload"]["capability_projection"]["tool_surface"] = [
      { "tool_name" => "compact_context" },
    ]

    result = run_runtime_execution(payload)

    assert_equal "failed", result.fetch("status")

    report = result.fetch("reports").last

    assert_equal "agent_program_failed", report.fetch("method_id")
    assert_equal "execute_program_tool", report.fetch("request_kind")
    assert_equal "tool_not_allowed", report.dig("error_payload", "code")
  end

  private

  def run_runtime_execution(payload)
    runtime_execution = nil

    assert_enqueued_jobs 1 do
      runtime_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: payload)
    end

    perform_enqueued_jobs

    runtime_execution.reload.attributes.slice("status", "reports")
  end

  def normalize_prepare_round_report(report)
    normalized = report.deep_dup
    normalized.delete("protocol_message_id")
    normalized["response_payload"] = {
      "status" => normalized.fetch("response_payload").fetch("status"),
      "messages" => normalized.fetch("response_payload").fetch("messages").map { |entry| entry.slice("role") },
      "tool_surface" => normalized.fetch("response_payload").fetch("tool_surface").map { |entry| entry.slice("tool_name") },
      "summary_artifacts" => normalized.fetch("response_payload").fetch("summary_artifacts"),
      "trace" => normalized.fetch("response_payload").fetch("trace").map { |entry| entry.slice("hook") },
    }
    normalized
  end

  def normalize_program_tool_report(report)
    normalized = report.deep_dup
    normalized.delete("protocol_message_id")
    normalized["response_payload"] = {
      "status" => normalized.fetch("response_payload").fetch("status"),
      "program_tool_call" => normalized.fetch("response_payload").fetch("program_tool_call"),
      "result" => normalized.fetch("response_payload").fetch("result"),
      "output_chunks" => normalized.fetch("response_payload").fetch("output_chunks"),
      "summary_artifacts" => normalized.fetch("response_payload").fetch("summary_artifacts"),
    }
    normalized
  end
end
