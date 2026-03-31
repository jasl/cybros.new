require "test_helper"

class RuntimeProgramContractTest < ActiveSupport::TestCase
  test "prepare_round mailbox work emits the frozen completed report shape" do
    result = run_runtime_execution(shared_contract_fixture("core_matrix_fenix_prepare_round_mailbox_item_v1"))

    report = result.fetch("reports").last

    assert_equal shared_contract_fixture("fenix_prepare_round_report_v1"), normalize_prepare_round_report(report)
  end

  test "execute_program_tool mailbox work emits the frozen completed report shape" do
    result = run_runtime_execution(shared_contract_fixture("core_matrix_fenix_execute_program_tool_mailbox_item_v1"))

    report = result.fetch("reports").last

    assert_equal shared_contract_fixture("fenix_execute_program_tool_report_v1"), normalize_program_tool_report(report)
  end

  test "execute_program_tool mailbox work rejects tools outside the visible program surface" do
    payload = shared_contract_fixture("core_matrix_fenix_execute_program_tool_mailbox_item_v1")
    payload["payload"]["agent_context"]["allowed_tool_names"] = ["compact_context"]

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
      "messages" => normalized.fetch("response_payload").fetch("messages").map { |entry| entry.slice("role") },
      "program_tools" => normalized.fetch("response_payload").fetch("program_tools").map { |entry| entry.slice("tool_name") },
      "likely_model" => normalized.fetch("response_payload").fetch("likely_model"),
      "trace" => normalized.fetch("response_payload").fetch("trace").map { |entry| entry.slice("hook") },
    }
    normalized
  end

  def normalize_program_tool_report(report)
    normalized = report.deep_dup
    normalized.delete("protocol_message_id")
    normalized
  end
end
