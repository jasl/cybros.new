module Fenix
  module Hooks
    class ToolResultProjectionRegistry
      REGISTRY = {
        "browser_close" => :project_browser_close,
        "browser_get_content" => :project_browser_get_content,
        "browser_list" => :project_browser_list,
        "browser_navigate" => :project_browser_navigate,
        "browser_open" => :project_browser_open,
        "browser_screenshot" => :project_browser_screenshot,
        "browser_session_info" => :project_browser_session_info,
        "calculator" => :project_calculator,
        "command_run_list" => :project_command_run_list,
        "command_run_read_output" => :project_command_run_read_output,
        "command_run_terminate" => :project_command_run_terminate,
        "command_run_wait" => :project_command_run_wait,
        "exec_command" => :project_exec_command,
        "firecrawl_scrape" => :project_firecrawl_scrape,
        "firecrawl_search" => :project_search_results,
        "memory_append_daily" => :project_memory_store,
        "memory_compact_summary" => :project_memory_compact_summary,
        "memory_get" => :project_memory_get,
        "memory_list" => :project_memory_list,
        "memory_search" => :project_memory_search,
        "memory_store" => :project_memory_store,
        "process_exec" => :project_process_exec,
        "process_list" => :project_process_list,
        "process_proxy_info" => :project_process_proxy_info,
        "process_read_output" => :project_process_read_output,
        "web_fetch" => :project_web_fetch,
        "web_search" => :project_search_results,
        "workspace_find" => :project_workspace_find,
        "workspace_read" => :project_workspace_read,
        "workspace_stat" => :project_workspace_stat,
        "workspace_tree" => :project_workspace_tree,
        "workspace_write" => :project_workspace_write,
        "write_stdin" => :project_write_stdin,
      }.freeze

      def self.fetch!(tool_name)
        REGISTRY.fetch(tool_name) do
          raise ArgumentError, "unsupported tool projection #{tool_name}"
        end
      end
    end
  end
end
