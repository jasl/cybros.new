require "test_helper"

module ExecutorPrograms
  class RecordCapabilitiesTest < ActiveSupport::TestCase
    test "records executor program capabilities independently from agent program versions" do
      executor_program = create_execution_runtime!(
        capability_payload: { "attachment_access" => { "request_attachment" => false } },
        tool_catalog: []
      )
      expected_contract = RuntimeCapabilityContract.build(
        execution_runtime: executor_program,
        execution_capability_payload: { attachment_access: { request_attachment: true } },
        execution_tool_catalog: [
          {
            tool_name: "exec_command",
            tool_kind: "execution_runtime",
            implementation_source: "execution_runtime",
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
            tool_kind: "execution_runtime",
            implementation_source: "execution_runtime",
            implementation_ref: "runtime/exec_command",
            input_schema: { type: "object", properties: {} },
            result_schema: { type: "object", properties: {} },
            streaming_support: false,
            idempotency_policy: "best_effort",
          },
        ]
      )

      assert_equal expected_contract.execution_plane.fetch("capability_payload"), updated.capability_payload
      assert_equal expected_contract.execution_plane.fetch("tool_catalog"), updated.tool_catalog
    end
  end
end
