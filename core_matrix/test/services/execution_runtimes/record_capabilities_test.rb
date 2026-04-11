require "test_helper"

module ExecutionRuntimes
  class RecordCapabilitiesTest < ActiveSupport::TestCase
    test "records execution runtime capabilities independently from agent snapshots" do
      execution_runtime = create_execution_runtime!(
        capability_payload: { "attachment_access" => { "request_attachment" => false } },
        tool_catalog: []
      )
      expected_contract = RuntimeCapabilityContract.build(
        execution_runtime: execution_runtime,
        execution_runtime_capability_payload: { attachment_access: { request_attachment: true } },
        execution_runtime_tool_catalog: [
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

      updated = ExecutionRuntimes::RecordCapabilities.call(
        execution_runtime: execution_runtime,
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

      assert_equal expected_contract.execution_runtime_plane.fetch("capability_payload"), updated.capability_payload
      assert_equal expected_contract.execution_runtime_plane.fetch("tool_catalog"), updated.tool_catalog
    end
  end
end
