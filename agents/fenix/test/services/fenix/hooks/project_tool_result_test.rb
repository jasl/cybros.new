require "test_helper"

class Fenix::Hooks::ProjectToolResultTest < ActiveSupport::TestCase
  test "projects calculator results through the registry-backed dispatcher" do
    projection = Fenix::Hooks::ProjectToolResult.call(
      tool_call: { "tool_name" => "calculator" },
      tool_result: 4
    )

    assert_equal "calculator", projection.fetch("tool_name")
    assert_equal "The calculator returned 4.", projection.fetch("content")
  end

  test "reuses the shared search projector for web and firecrawl search tools" do
    tool_result = {
      "provider" => "demo",
      "query" => "fenix",
      "results" => [
        { "title" => "Fenix", "url" => "https://example.test/fenix" },
      ],
    }

    web_projection = Fenix::Hooks::ProjectToolResult.call(
      tool_call: { "tool_name" => "web_search" },
      tool_result: tool_result
    )
    firecrawl_projection = Fenix::Hooks::ProjectToolResult.call(
      tool_call: { "tool_name" => "firecrawl_search" },
      tool_result: tool_result
    )

    assert_equal "1. Fenix - https://example.test/fenix", web_projection.fetch("content")
    assert_equal web_projection.fetch("content"), firecrawl_projection.fetch("content")
    assert_equal "demo", firecrawl_projection.fetch("provider")
  end

  test "raises for unsupported tool projections" do
    error = assert_raises(ArgumentError) do
      Fenix::Hooks::ProjectToolResult.call(
        tool_call: { "tool_name" => "workspace_delete" },
        tool_result: {}
      )
    end

    assert_includes error.message, "workspace_delete"
  end
end
