require "test_helper"

class RuntimeCapabilities::ComposeEffectiveToolCatalogTest < ActiveSupport::TestCase
  test "delegates effective tool catalog rendering to the shared runtime capability contract" do
    registration = register_agent_runtime!(
      environment_tool_catalog: [
        {
          "tool_name" => "shell_exec",
          "tool_kind" => "environment_runtime",
          "implementation_source" => "execution_environment",
          "implementation_ref" => "env/shell_exec",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      tool_catalog: default_tool_catalog("shell_exec", "compact_context")
    )
    contract = RuntimeCapabilityContract.build(
      execution_environment: registration[:execution_environment],
      capability_snapshot: registration[:capability_snapshot]
    )

    assert_equal(
      contract.effective_tool_catalog,
      RuntimeCapabilities::ComposeEffectiveToolCatalog.call(
        execution_environment: registration[:execution_environment],
        capability_snapshot: registration[:capability_snapshot]
      )
    )
  end
end
