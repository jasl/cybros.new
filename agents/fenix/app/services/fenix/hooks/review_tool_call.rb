module Fenix
  module Hooks
    class ReviewToolCall
      UnsupportedToolError = Class.new(StandardError)
      ToolNotVisibleError = Class.new(UnsupportedToolError)

      SUPPORTED_TOOLS = {
        "browser_close" => true,
        "browser_get_content" => true,
        "browser_navigate" => true,
        "browser_open" => true,
        "browser_screenshot" => true,
        "calculator" => true,
        "exec_command" => true,
        "firecrawl_scrape" => true,
        "firecrawl_search" => true,
        "memory_get" => true,
        "memory_append_daily" => true,
        "memory_compact_summary" => true,
        "memory_list" => true,
        "memory_search" => true,
        "memory_store" => true,
        "process_exec" => true,
        "web_fetch" => true,
        "web_search" => true,
        "workspace_find" => true,
        "workspace_read" => true,
        "workspace_stat" => true,
        "workspace_tree" => true,
        "workspace_write" => true,
        "write_stdin" => true,
      }.freeze

      def self.call(tool_call:, allowed_tool_names:)
        tool_call = tool_call.deep_stringify_keys
        tool_name = tool_call.fetch("tool_name")
        raise UnsupportedToolError, "unsupported tool #{tool_name}" unless SUPPORTED_TOOLS.key?(tool_name)
        unless Array(allowed_tool_names).map(&:to_s).include?(tool_name)
          raise ToolNotVisibleError, "tool #{tool_name} is not visible for this assignment"
        end

        tool_call
      end
    end
  end
end
