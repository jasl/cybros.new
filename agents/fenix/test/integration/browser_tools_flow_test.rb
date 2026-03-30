require "test_helper"

class BrowserToolsFlowTest < ActiveSupport::TestCase
  test "browser_open routes through the browser session manager" do
    routed_call = nil
    original_call = Fenix::Browser::SessionManager.method(:call)

    Fenix::Browser::SessionManager.define_singleton_method(:call) do |**kwargs|
      routed_call = kwargs
      {
        "browser_session_id" => "browser-session-1",
        "current_url" => kwargs[:url],
      }
    end

    begin
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "browser_open",
            "url" => "https://example.com",
          },
          agent_context: default_agent_context.merge(
            "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["browser_open"]
          )
        )
      )

      invocation = result.reports.last.fetch("terminal_payload").fetch("tool_invocations").fetch(0)

      assert_equal "completed", result.status
      assert_equal "browser-session-1", invocation.dig("response_payload", "browser_session_id")
      assert_equal "https://example.com", routed_call.fetch(:url)
    ensure
      Fenix::Browser::SessionManager.define_singleton_method(:call, original_call)
    end
  end

  test "browser_get_content routes through the browser session manager" do
    original_call = Fenix::Browser::SessionManager.method(:call)

    Fenix::Browser::SessionManager.define_singleton_method(:call) do |**kwargs|
      {
        "browser_session_id" => kwargs[:browser_session_id],
        "current_url" => "https://example.com",
        "content" => "Example page",
      }
    end

    begin
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "browser_get_content",
            "browser_session_id" => "browser-session-1",
          },
          agent_context: default_agent_context.merge(
            "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["browser_get_content"]
          )
        )
      )

      assert_equal "completed", result.status
      assert_equal "Example page", result.output
    ensure
      Fenix::Browser::SessionManager.define_singleton_method(:call, original_call)
    end
  end

  test "browser_screenshot routes through the browser session manager" do
    original_call = Fenix::Browser::SessionManager.method(:call)

    Fenix::Browser::SessionManager.define_singleton_method(:call) do |**kwargs|
      {
        "browser_session_id" => kwargs[:browser_session_id],
        "current_url" => "https://example.com",
        "mime_type" => "image/png",
        "image_base64" => "cG5n",
      }
    end

    begin
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: runtime_assignment_payload(
          mode: "deterministic_tool",
          task_payload: {
            "tool_name" => "browser_screenshot",
            "browser_session_id" => "browser-session-1",
          },
          agent_context: default_agent_context.merge(
            "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["browser_screenshot"]
          )
        )
      )

      invocation = result.reports.last.fetch("terminal_payload").fetch("tool_invocations").fetch(0)

      assert_equal "completed", result.status
      assert_equal "image/png", invocation.dig("response_payload", "mime_type")
    ensure
      Fenix::Browser::SessionManager.define_singleton_method(:call, original_call)
    end
  end
end
