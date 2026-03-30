require "test_helper"

module ExecutionEnvironments
  class RecordCapabilitiesTest < ActiveSupport::TestCase
    test "records environment capabilities independently from deployment capability snapshots" do
      environment = create_execution_environment!(
        capability_payload: { "conversation_attachment_upload" => false },
        tool_catalog: []
      )
      expected_contract = RuntimeCapabilityContract.build(
        execution_environment: environment,
        environment_capability_payload: { conversation_attachment_upload: true },
        environment_tool_catalog: [
          {
            tool_name: "exec_command",
            tool_kind: "environment_runtime",
            implementation_source: "environment",
            implementation_ref: "runtime/exec_command",
            input_schema: { type: "object", properties: {} },
            result_schema: { type: "object", properties: {} },
            streaming_support: false,
            idempotency_policy: "best_effort",
          },
        ]
      )

      updated = ExecutionEnvironments::RecordCapabilities.call(
        execution_environment: environment,
        capability_payload: { conversation_attachment_upload: true },
        tool_catalog: [
          {
            tool_name: "exec_command",
            tool_kind: "environment_runtime",
            implementation_source: "environment",
            implementation_ref: "runtime/exec_command",
            input_schema: { type: "object", properties: {} },
            result_schema: { type: "object", properties: {} },
            streaming_support: false,
            idempotency_policy: "best_effort",
          },
        ]
      )

      assert_equal expected_contract.environment_plane.fetch("capability_payload"), updated.capability_payload
      assert_equal expected_contract.environment_plane.fetch("tool_catalog"), updated.tool_catalog
    end
  end
end
