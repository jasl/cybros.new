require "test_helper"

module ExecutionEnvironments
  class RecordCapabilitiesTest < ActiveSupport::TestCase
    test "records environment capabilities independently from deployment capability snapshots" do
      environment = create_execution_environment!(
        capability_payload: { "conversation_attachment_upload" => false },
        tool_catalog: []
      )

      updated = ExecutionEnvironments::RecordCapabilities.call(
        execution_environment: environment,
        capability_payload: { "conversation_attachment_upload" => true },
        tool_catalog: [
          {
            "tool_name" => "shell_exec",
            "tool_kind" => "environment_runtime",
            "implementation_source" => "environment",
            "implementation_ref" => "runtime/shell_exec",
            "input_schema" => { "type" => "object", "properties" => {} },
            "result_schema" => { "type" => "object", "properties" => {} },
            "streaming_support" => false,
            "idempotency_policy" => "best_effort",
          },
        ]
      )

      assert_equal true, updated.capability_payload["conversation_attachment_upload"]
      assert_equal ["shell_exec"], updated.tool_catalog.map { |entry| entry.fetch("tool_name") }
    end
  end
end
