require "test_helper"

class RuntimeCapabilities::ResolveToolExecutionPolicyTest < ActiveSupport::TestCase
  test "defaults built-in tools to parallel_safe false" do
    policy = RuntimeCapabilities::ResolveToolExecutionPolicy.call(
      tool_entry: {
        "tool_name" => "compact_context",
        "implementation_source" => "agent",
      }
    )

    assert_equal({ "parallel_safe" => false }, policy)
  end

  test "forces mcp tools to parallel_safe false before overlays are applied" do
    policy = RuntimeCapabilities::ResolveToolExecutionPolicy.call(
      tool_entry: {
        "tool_name" => "remote_echo",
        "implementation_source" => "mcp",
        "execution_policy" => { "parallel_safe" => true },
      }
    )

    assert_equal({ "parallel_safe" => false }, policy)
  end

  test "applies a matching overlay after source defaults" do
    policy = RuntimeCapabilities::ResolveToolExecutionPolicy.call(
      tool_entry: {
        "tool_name" => "remote_echo",
        "implementation_source" => "mcp",
        "mcp_server_slug" => "internal-docs",
      },
      overlays: [
        {
          "match" => {
            "tool_source" => "mcp",
            "server_slug" => "internal-docs",
            "tool_name" => "remote_echo",
          },
          "execution_policy" => {
            "parallel_safe" => true,
          },
        },
      ]
    )

    assert_equal({ "parallel_safe" => true }, policy)
  end

  test "ignores unmatched overlays" do
    policy = RuntimeCapabilities::ResolveToolExecutionPolicy.call(
      tool_entry: {
        "tool_name" => "remote_echo",
        "implementation_source" => "mcp",
        "mcp_server_slug" => "public-docs",
      },
      overlays: [
        {
          "match" => {
            "tool_source" => "mcp",
            "server_slug" => "internal-docs",
            "tool_name" => "remote_echo",
          },
          "execution_policy" => {
            "parallel_safe" => true,
          },
        },
      ]
    )

    assert_equal({ "parallel_safe" => false }, policy)
  end
end
