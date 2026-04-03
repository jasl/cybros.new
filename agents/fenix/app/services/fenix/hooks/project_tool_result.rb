module Fenix
  module Hooks
    class ProjectToolResult
      def self.call(tool_call:, tool_result:)
        tool_name = tool_call.fetch("tool_name")
        projector = Fenix::Hooks::ToolResultProjectionRegistry.fetch!(tool_name)

        public_send(projector, tool_name:, tool_result:)
      end

      def self.project_calculator(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "The calculator returned #{tool_result}.",
        }
      end

      def self.project_exec_command(tool_name:, tool_result:)
        stdout = tool_result.fetch("stdout", "")
        stderr = tool_result.fetch("stderr", "")
        output_streamed = tool_result.fetch("output_streamed", stdout.present? || stderr.present?)

        if tool_result["attached"] == true && !tool_result.fetch("session_closed", false)
          {
            "tool_name" => tool_name,
            "content" => "Command run started.",
            "command_run_id" => tool_result.fetch("command_run_id"),
            "attached" => true,
            "session_closed" => false,
          }
        else
          {
            "tool_name" => tool_name,
            "content" => command_content(exit_status: tool_result.fetch("exit_status"), output_streamed:),
            "command_run_id" => tool_result["command_run_id"],
            "exit_status" => tool_result.fetch("exit_status"),
            "output_streamed" => output_streamed,
            "stdout_bytes" => tool_result.fetch("stdout_bytes", stdout.bytesize),
            "stderr_bytes" => tool_result.fetch("stderr_bytes", stderr.bytesize),
          }
        end
      end

      def self.project_command_run_list(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Listed #{tool_result.fetch("entries").size} attached command runs.",
          "entries" => tool_result.fetch("entries"),
        }
      end

      def self.project_command_run_read_output(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Read buffered output for command run #{tool_result.fetch("command_run_id")}.",
          "command_run_id" => tool_result.fetch("command_run_id"),
          "session_closed" => tool_result.fetch("session_closed"),
          "stdout_tail" => tool_result.fetch("stdout_tail"),
          "stderr_tail" => tool_result.fetch("stderr_tail"),
          "stdout_bytes" => tool_result.fetch("stdout_bytes"),
          "stderr_bytes" => tool_result.fetch("stderr_bytes"),
        }
      end

      def self.project_command_run_terminate(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Terminated command run #{tool_result.fetch("command_run_id")}.",
          "command_run_id" => tool_result.fetch("command_run_id"),
          "terminated" => tool_result.fetch("terminated"),
          "session_closed" => tool_result.fetch("session_closed"),
          "exit_status" => tool_result["exit_status"],
          "stdout_bytes" => tool_result.fetch("stdout_bytes"),
          "stderr_bytes" => tool_result.fetch("stderr_bytes"),
          "stdout_tail" => tool_result.fetch("stdout_tail"),
          "stderr_tail" => tool_result.fetch("stderr_tail"),
        }.compact
      end

      def self.project_command_run_wait(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => attached_session_content(
            exit_status: tool_result.fetch("exit_status"),
            output_streamed: tool_result.fetch("output_streamed")
          ),
          "command_run_id" => tool_result.fetch("command_run_id"),
          "session_closed" => tool_result.fetch("session_closed"),
          "exit_status" => tool_result.fetch("exit_status"),
          "output_streamed" => tool_result.fetch("output_streamed"),
          "stdout_bytes" => tool_result.fetch("stdout_bytes"),
          "stderr_bytes" => tool_result.fetch("stderr_bytes"),
          "stdout_tail" => tool_result.fetch("stdout_tail"),
          "stderr_tail" => tool_result.fetch("stderr_tail"),
        }
      end

      def self.project_write_stdin(tool_name:, tool_result:)
        if tool_result.fetch("session_closed", false)
          {
            "tool_name" => tool_name,
            "content" => attached_session_content(
              exit_status: tool_result.fetch("exit_status"),
              output_streamed: tool_result.fetch("output_streamed", false)
            ),
            "command_run_id" => tool_result.fetch("command_run_id"),
            "session_closed" => true,
            "exit_status" => tool_result.fetch("exit_status"),
            "output_streamed" => tool_result.fetch("output_streamed", false),
            "stdout_bytes" => tool_result.fetch("stdout_bytes", 0),
            "stderr_bytes" => tool_result.fetch("stderr_bytes", 0),
            "stdin_bytes" => tool_result.fetch("stdin_bytes", 0),
          }
        else
          {
            "tool_name" => tool_name,
            "content" => "Wrote #{tool_result.fetch("stdin_bytes", 0)} bytes to command run.",
            "command_run_id" => tool_result.fetch("command_run_id"),
            "session_closed" => false,
            "stdin_bytes" => tool_result.fetch("stdin_bytes", 0),
          }
        end
      end

      def self.project_process_exec(tool_name:, tool_result:)
        content = "Background service started as process run #{tool_result.fetch("process_run_id")}."
        if tool_result["proxy_path"].present?
          content = "#{content} Available at #{tool_result.fetch("proxy_path")}."
        end

        {
          "tool_name" => tool_name,
          "content" => content,
          "process_run_id" => tool_result.fetch("process_run_id"),
          "lifecycle_state" => tool_result.fetch("lifecycle_state"),
          "proxy_path" => tool_result["proxy_path"],
          "proxy_target_url" => tool_result["proxy_target_url"],
        }
      end

      def self.project_process_list(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Listed #{tool_result.fetch("entries").size} active process runs.",
          "entries" => tool_result.fetch("entries"),
        }
      end

      def self.project_process_proxy_info(tool_name:, tool_result:)
        content =
          if tool_result["proxy_path"].present?
            "Process run #{tool_result.fetch("process_run_id")} is available at #{tool_result.fetch("proxy_path")}."
          else
            "Process run #{tool_result.fetch("process_run_id")} has no proxy route."
          end

        {
          "tool_name" => tool_name,
          "content" => content,
          "process_run_id" => tool_result.fetch("process_run_id"),
          "proxy_path" => tool_result["proxy_path"],
          "proxy_target_url" => tool_result["proxy_target_url"],
        }.compact
      end

      def self.project_process_read_output(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Read buffered output for process run #{tool_result.fetch("process_run_id")}.",
          "process_run_id" => tool_result.fetch("process_run_id"),
          "stdout_tail" => tool_result.fetch("stdout_tail"),
          "stderr_tail" => tool_result.fetch("stderr_tail"),
          "stdout_bytes" => tool_result.fetch("stdout_bytes"),
          "stderr_bytes" => tool_result.fetch("stderr_bytes"),
          "lifecycle_state" => tool_result.fetch("lifecycle_state"),
        }
      end

      def self.project_browser_open(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Browser session #{tool_result.fetch("browser_session_id")} opened at #{tool_result.fetch("current_url")}.",
          "browser_session_id" => tool_result.fetch("browser_session_id"),
          "current_url" => tool_result.fetch("current_url"),
        }
      end

      def self.project_browser_list(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Listed #{tool_result.fetch("entries").size} browser sessions.",
          "entries" => tool_result.fetch("entries"),
        }
      end

      def self.project_browser_navigate(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Browser session navigated to #{tool_result.fetch("current_url")}.",
          "browser_session_id" => tool_result.fetch("browser_session_id"),
          "current_url" => tool_result.fetch("current_url"),
        }
      end

      def self.project_browser_get_content(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => tool_result.fetch("content"),
          "browser_session_id" => tool_result.fetch("browser_session_id"),
          "current_url" => tool_result.fetch("current_url"),
        }
      end

      def self.project_browser_screenshot(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Captured screenshot for browser session #{tool_result.fetch("browser_session_id")}.",
          "browser_session_id" => tool_result.fetch("browser_session_id"),
          "current_url" => tool_result.fetch("current_url"),
          "mime_type" => tool_result.fetch("mime_type"),
          "image_base64" => tool_result.fetch("image_base64"),
        }
      end

      def self.project_browser_close(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Browser session #{tool_result.fetch("browser_session_id")} closed.",
          "browser_session_id" => tool_result.fetch("browser_session_id"),
          "closed" => tool_result.fetch("closed"),
        }
      end

      def self.project_browser_session_info(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Browser session #{tool_result.fetch("browser_session_id")} is at #{tool_result.fetch("current_url")}.",
          "browser_session_id" => tool_result.fetch("browser_session_id"),
          "current_url" => tool_result["current_url"],
        }.compact
      end

      def self.project_web_fetch(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => tool_result.fetch("content"),
          "url" => tool_result.fetch("url"),
          "content_type" => tool_result.fetch("content_type"),
          "redirects" => tool_result.fetch("redirects"),
        }
      end

      def self.project_workspace_read(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Workspace file #{tool_result.fetch("path")}:\n#{tool_result.fetch("content")}",
          "path" => tool_result.fetch("path"),
          "file_content" => tool_result.fetch("content"),
          "bytes_read" => tool_result.fetch("bytes_read"),
        }
      end

      def self.project_workspace_write(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Wrote #{tool_result.fetch("bytes_written")} bytes to workspace file #{tool_result.fetch("path")}.",
          "path" => tool_result.fetch("path"),
          "bytes_written" => tool_result.fetch("bytes_written"),
        }
      end

      def self.project_workspace_tree(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Listed #{tool_result.fetch("entries").size} workspace entries under #{tool_result.fetch("path")}.",
          "path" => tool_result.fetch("path"),
          "entries" => tool_result.fetch("entries"),
        }
      end

      def self.project_workspace_stat(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Workspace path #{tool_result.fetch("path")} is a #{tool_result.fetch("node_type")}.",
          "path" => tool_result.fetch("path"),
          "node_type" => tool_result.fetch("node_type"),
          "size_bytes" => tool_result.fetch("size_bytes"),
        }
      end

      def self.project_workspace_find(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Found #{tool_result.fetch("matches").size} workspace paths matching #{tool_result.fetch("query")}.",
          "path" => tool_result.fetch("path"),
          "query" => tool_result.fetch("query"),
          "matches" => tool_result.fetch("matches"),
        }
      end

      def self.project_memory_get(tool_name:, tool_result:)
        sections = []
        sections << "Root memory:\n#{tool_result.fetch("root_memory")}" if tool_result["root_memory"].present?
        sections << "Conversation summary:\n#{tool_result.fetch("conversation_summary")}" if tool_result["conversation_summary"].present?
        sections << "Conversation memory:\n#{tool_result.fetch("conversation_memory")}" if tool_result["conversation_memory"].present?

        {
          "tool_name" => tool_name,
          "content" => sections.join("\n\n"),
          "scope" => tool_result.fetch("scope"),
          "root_memory" => tool_result["root_memory"],
          "conversation_summary" => tool_result["conversation_summary"],
          "conversation_memory" => tool_result["conversation_memory"],
        }.compact
      end

      def self.project_memory_search(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Found #{tool_result.fetch("matches").size} memory matches for #{tool_result.fetch("query")}.",
          "query" => tool_result.fetch("query"),
          "matches" => tool_result.fetch("matches"),
        }
      end

      def self.project_memory_list(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Listed #{tool_result.fetch("entries").size} memory entries.",
          "scope" => tool_result.fetch("scope"),
          "entries" => tool_result.fetch("entries"),
        }
      end

      def self.project_memory_store(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Stored memory at #{tool_result.fetch("memory_path")}.",
          "scope" => tool_result.fetch("scope"),
          "memory_path" => tool_result.fetch("memory_path"),
          "bytes_written" => tool_result.fetch("bytes_written"),
        }
      end

      def self.project_memory_compact_summary(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Updated #{tool_result.fetch("scope")} summary at #{tool_result.fetch("memory_path")}.",
          "scope" => tool_result.fetch("scope"),
          "memory_path" => tool_result.fetch("memory_path"),
          "bytes_written" => tool_result.fetch("bytes_written"),
        }
      end

      def self.project_search_results(tool_name:, tool_result:)
        results = tool_result.fetch("results")
        content =
          if results.empty?
            "No search results."
          else
            results.map.with_index(1) do |result, index|
              "#{index}. #{result.fetch("title", result.fetch("url", "Untitled"))} - #{result.fetch("url", "")}".strip
            end.join("\n")
          end

        {
          "tool_name" => tool_name,
          "content" => content,
          "provider" => tool_result.fetch("provider"),
          "query" => tool_result.fetch("query"),
          "results" => results,
        }
      end

      def self.project_firecrawl_scrape(tool_name:, tool_result:)
        markdown = tool_result.fetch("markdown")

        {
          "tool_name" => tool_name,
          "content" => markdown,
          "url" => tool_result.fetch("url"),
          "markdown" => markdown,
          "metadata" => tool_result.fetch("metadata"),
        }
      end

      def self.command_content(exit_status:, output_streamed:)
        return "Command exited with status #{exit_status}." unless output_streamed

        "Command exited with status #{exit_status} after streaming output."
      end

      def self.attached_session_content(exit_status:, output_streamed:)
        return "Command run completed with status #{exit_status}." unless output_streamed

        "Command run completed with status #{exit_status} after streaming output."
      end
    end
  end
end
