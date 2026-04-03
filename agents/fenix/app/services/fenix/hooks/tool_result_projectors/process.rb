module Fenix
  module Hooks
    module ToolResultProjectors
      module Process
        class << self
          def call(tool_name:, tool_result:)
            case tool_name
            when "process_exec"
              {
                "tool_name" => tool_name,
                "content" => process_exec_content(tool_result),
                "process_run_id" => tool_result.fetch("process_run_id"),
                "lifecycle_state" => tool_result.fetch("lifecycle_state"),
                "proxy_path" => tool_result["proxy_path"],
                "proxy_target_url" => tool_result["proxy_target_url"],
              }
            when "process_list"
              {
                "tool_name" => tool_name,
                "content" => "Listed #{tool_result.fetch("entries").size} active process runs.",
                "entries" => tool_result.fetch("entries"),
              }
            when "process_proxy_info"
              {
                "tool_name" => tool_name,
                "content" => process_proxy_info_content(tool_result),
                "process_run_id" => tool_result.fetch("process_run_id"),
                "proxy_path" => tool_result["proxy_path"],
                "proxy_target_url" => tool_result["proxy_target_url"],
              }.compact
            when "process_read_output"
              {
                "tool_name" => tool_name,
                "content" => "Read buffered output for process run #{tool_result.fetch("process_run_id")}.",
                "process_run_id" => tool_result.fetch("process_run_id"),
                "exit_status" => tool_result["exit_status"],
                "stdout_tail" => tool_result.fetch("stdout_tail"),
                "stderr_tail" => tool_result.fetch("stderr_tail"),
                "stdout_bytes" => tool_result.fetch("stdout_bytes"),
                "stderr_bytes" => tool_result.fetch("stderr_bytes"),
                "lifecycle_state" => tool_result.fetch("lifecycle_state"),
              }
            else
              raise ArgumentError, "unsupported process projection #{tool_name}"
            end
          end

          private

          def process_exec_content(tool_result)
            content = "Background service started as process run #{tool_result.fetch("process_run_id")}."
            return content unless tool_result["proxy_path"].present?

            "#{content} Available at #{tool_result.fetch("proxy_path")}."
          end

          def process_proxy_info_content(tool_result)
            if tool_result["proxy_path"].present?
              "Process run #{tool_result.fetch("process_run_id")} is available at #{tool_result.fetch("proxy_path")}."
            else
              "Process run #{tool_result.fetch("process_run_id")} has no proxy route."
            end
          end
        end
      end
    end
  end
end
