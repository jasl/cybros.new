require "securerandom"

module Fenix
  module Runtime
    module Assignments
      class BuildToolCall
        def self.call(...)
          new(...).call
        end

        def initialize(task_payload:)
          @task_payload = task_payload.deep_stringify_keys
        end

        def call
          tool_name = @task_payload["tool_name"] || "calculator"

          {
            "call_id" => "tool-call-#{SecureRandom.uuid}",
            "tool_name" => tool_name,
            "arguments" => arguments_for(tool_name),
          }
        end

        private

        def arguments_for(tool_name)
          case tool_name
          when "calculator"
            { "expression" => @task_payload["expression"] || "2 + 2" }
          when "exec_command"
            {
              "command_line" => @task_payload["command_line"] || "printf 'hello\\n'",
              "timeout_seconds" => @task_payload["timeout_seconds"] || 30,
              "pty" => @task_payload["pty"] || false,
            }
          when "command_run_list"
            {}
          when "command_run_read_output", "command_run_terminate", "command_run_wait"
            {
              "command_run_id" => @task_payload["command_run_id"],
              "timeout_seconds" => @task_payload["timeout_seconds"] || 30,
            }.compact
          when "write_stdin"
            {
              "command_run_id" => @task_payload["command_run_id"],
              "text" => @task_payload["text"].to_s,
              "eof" => @task_payload["eof"] || false,
              "wait_for_exit" => @task_payload["wait_for_exit"] || false,
              "timeout_seconds" => @task_payload["timeout_seconds"] || 30,
            }
          when "process_exec"
            {
              "command_line" => @task_payload["command_line"] || "bin/dev",
              "kind" => @task_payload["kind"] || "background_service",
              "proxy_port" => @task_payload["proxy_port"],
            }
          when "process_list"
            {}
          when "process_read_output", "process_proxy_info"
            {
              "process_run_id" => @task_payload["process_run_id"],
            }
          when "workspace_read"
            {
              "path" => @task_payload["path"] || "README.md",
            }
          when "workspace_tree", "workspace_stat"
            {
              "path" => @task_payload["path"] || ".",
            }
          when "workspace_find"
            {
              "path" => @task_payload["path"] || ".",
              "query" => @task_payload["query"].to_s,
              "limit" => @task_payload["limit"] || 20,
            }
          when "workspace_write"
            {
              "path" => @task_payload["path"] || "notes/output.txt",
              "content" => @task_payload["content"].to_s,
            }
          when "memory_append_daily"
            {
              "text" => @task_payload["text"].to_s,
              "title" => @task_payload["title"].to_s,
            }
          when "memory_compact_summary"
            {
              "text" => @task_payload["text"].to_s,
              "scope" => @task_payload["scope"] || "conversation",
            }
          when "memory_get"
            {
              "scope" => @task_payload["scope"] || "all",
            }
          when "memory_list"
            {
              "scope" => @task_payload["scope"] || "all",
            }
          when "memory_search"
            {
              "query" => @task_payload["query"].to_s,
              "limit" => @task_payload["limit"] || 5,
            }
          when "memory_store"
            {
              "text" => @task_payload["text"].to_s,
              "title" => @task_payload["title"].to_s,
              "scope" => @task_payload["scope"] || "daily",
            }
          when "web_fetch"
            {
              "url" => @task_payload["url"] || "https://example.com",
            }
          when "web_search", "firecrawl_search"
            {
              "query" => @task_payload["query"].to_s,
              "limit" => @task_payload["limit"] || 5,
              "provider" => @task_payload["provider"] || "firecrawl",
            }
          when "firecrawl_scrape"
            {
              "url" => @task_payload["url"] || "https://example.com",
              "formats" => Array(@task_payload["formats"]).presence || ["markdown"],
            }
          when "browser_open"
            {
              "url" => @task_payload["url"] || "https://example.com",
            }
          when "browser_list"
            {}
          when "browser_session_info"
            {
              "browser_session_id" => @task_payload["browser_session_id"],
            }
          when "browser_navigate"
            {
              "browser_session_id" => @task_payload["browser_session_id"],
              "url" => @task_payload["url"] || "https://example.com",
            }
          when "browser_get_content"
            {
              "browser_session_id" => @task_payload["browser_session_id"],
            }
          when "browser_screenshot"
            {
              "browser_session_id" => @task_payload["browser_session_id"],
              "full_page" => @task_payload["full_page"] != false,
            }
          when "browser_close"
            {
              "browser_session_id" => @task_payload["browser_session_id"],
            }
          else
            {}
          end
        end
      end
    end
  end
end
