require "test_helper"

module ExecutorPrograms
  class RecordCapabilitiesTest < ActiveSupport::TestCase
    test "records executor program capabilities independently from agent program versions" do
      executor_program = create_executor_program!(
        capability_payload: { "attachment_access" => { "request_attachment" => false } },
        tool_catalog: []
      )
      expected_contract = RuntimeCapabilityContract.build(
        executor_program: executor_program,
        executor_capability_payload: { attachment_access: { request_attachment: true } },
        executor_tool_catalog: [
          {
            tool_name: "exec_command",
            tool_kind: "executor_program",
            implementation_source: "executor_program",
            implementation_ref: "runtime/exec_command",
            input_schema: { type: "object", properties: {} },
            result_schema: { type: "object", properties: {} },
            streaming_support: false,
            idempotency_policy: "best_effort",
          },
        ]
      )

      updated = ExecutorPrograms::RecordCapabilities.call(
        executor_program: executor_program,
        capability_payload: { attachment_access: { request_attachment: true } },
        tool_catalog: [
          {
            tool_name: "exec_command",
            tool_kind: "executor_program",
            implementation_source: "executor_program",
            implementation_ref: "runtime/exec_command",
            input_schema: { type: "object", properties: {} },
            result_schema: { type: "object", properties: {} },
            streaming_support: false,
            idempotency_policy: "best_effort",
          },
        ]
      )

      assert_equal expected_contract.executor_plane.fetch("capability_payload"), updated.capability_payload
      assert_equal expected_contract.executor_plane.fetch("tool_catalog"), updated.tool_catalog
    end
  end
end
