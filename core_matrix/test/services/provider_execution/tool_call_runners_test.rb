require "test_helper"

class ProviderExecution::ToolCallRunnersTest < ActiveSupport::TestCase
  test "fetches runner classes for supported implementation source kinds" do
    assert_equal ProviderExecution::ToolCallRunners::MCP, ProviderExecution::ToolCallRunners.fetch!("mcp")
    assert_equal ProviderExecution::ToolCallRunners::AgentMediated, ProviderExecution::ToolCallRunners.fetch!("agent")
    assert_equal ProviderExecution::ToolCallRunners::AgentMediated, ProviderExecution::ToolCallRunners.fetch!("kernel")
    assert_equal ProviderExecution::ToolCallRunners::AgentMediated, ProviderExecution::ToolCallRunners.fetch!("execution_runtime")
    assert_equal ProviderExecution::ToolCallRunners::CoreMatrix, ProviderExecution::ToolCallRunners.fetch!("core_matrix")
  end

  test "raises for unsupported implementation source kinds" do
    error = assert_raises(ArgumentError) do
      ProviderExecution::ToolCallRunners.fetch!("manual_user")
    end

    assert_includes error.message, "manual_user"
  end
end
