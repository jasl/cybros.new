require "test_helper"

class WebToolsFlowTest < ActiveSupport::TestCase
  test "web_fetch routes through the local fetch service" do
    routed_call = nil
    original_call = Fenix::Web::Fetch.method(:call)

    Fenix::Web::Fetch.define_singleton_method(:call) do |**kwargs|
      routed_call = kwargs
      {
        "url" => kwargs.fetch(:url),
        "content" => "Fetched page",
        "content_type" => "text/plain",
        "redirects" => 0,
      }
    end

    begin
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "web_fetch",
            "url" => "https://example.com",
          },
          agent_context: default_agent_context.merge(
            "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["web_fetch"]
          )
        )
      )

      invocation = result.reports.last.fetch("terminal_payload").fetch("tool_invocations").fetch(0)

      assert_equal "completed", result.status
      assert_equal "Fetched page", result.output
      assert_equal "https://example.com", routed_call.fetch(:url)
      assert_equal "https://example.com", invocation.dig("response_payload", "url")
    ensure
      Fenix::Web::Fetch.define_singleton_method(:call, original_call)
    end
  end

  test "web_search routes through the generic search service" do
    routed_call = nil
    original_call = Fenix::Web::Search.method(:call)

    Fenix::Web::Search.define_singleton_method(:call) do |**kwargs|
      routed_call = kwargs
      {
        "provider" => kwargs.fetch(:provider),
        "query" => kwargs.fetch(:query),
        "results" => [
          {
            "url" => "https://example.com",
            "title" => "Example",
            "description" => "Search result",
          },
        ],
      }
    end

    begin
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "web_search",
            "query" => "agent frameworks",
          },
          agent_context: default_agent_context.merge(
            "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["web_search"]
          )
        )
      )

      invocation = result.reports.last.fetch("terminal_payload").fetch("tool_invocations").fetch(0)

      assert_equal "completed", result.status
      assert_equal "firecrawl", routed_call.fetch(:provider)
      assert_equal "agent frameworks", routed_call.fetch(:query)
      assert_equal "Example", invocation.dig("response_payload", "results", 0, "title")
    ensure
      Fenix::Web::Search.define_singleton_method(:call, original_call)
    end
  end

  test "firecrawl_search routes through the explicit firecrawl client" do
    original_call = Fenix::Web::FirecrawlClient.method(:search)

    Fenix::Web::FirecrawlClient.define_singleton_method(:search) do |**kwargs|
      {
        "success" => true,
        "data" => {
          "web" => [
            {
              "url" => "https://example.com",
              "title" => "Example",
              "description" => "Search result",
            },
          ],
        },
      }
    end

    begin
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "firecrawl_search",
            "query" => "agent frameworks",
          },
          agent_context: default_agent_context.merge(
            "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["firecrawl_search"]
          )
        )
      )

      invocation = result.reports.last.fetch("terminal_payload").fetch("tool_invocations").fetch(0)

      assert_equal "completed", result.status
      assert_equal "Example", invocation.dig("response_payload", "results", 0, "title")
    ensure
      Fenix::Web::FirecrawlClient.define_singleton_method(:search, original_call)
    end
  end

  test "firecrawl_scrape routes through the explicit firecrawl client" do
    original_call = Fenix::Web::FirecrawlClient.method(:scrape)

    Fenix::Web::FirecrawlClient.define_singleton_method(:scrape) do |**kwargs|
      {
        "success" => true,
        "data" => {
          "markdown" => "# Example",
          "metadata" => { "title" => "Example" },
        },
      }
    end

    begin
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "firecrawl_scrape",
            "url" => "https://example.com",
          },
          agent_context: default_agent_context.merge(
            "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["firecrawl_scrape"]
          )
        )
      )

      invocation = result.reports.last.fetch("terminal_payload").fetch("tool_invocations").fetch(0)

      assert_equal "completed", result.status
      assert_equal "# Example", result.output
      assert_equal "# Example", invocation.dig("response_payload", "markdown")
    ensure
      Fenix::Web::FirecrawlClient.define_singleton_method(:scrape, original_call)
    end
  end
end
