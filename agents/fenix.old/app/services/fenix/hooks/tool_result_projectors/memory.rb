module Fenix
  module Hooks
    module ToolResultProjectors
      module Memory
        class << self
          def call(tool_name:, tool_result:)
            case tool_name
            when "memory_get"
              project_memory_get(tool_name:, tool_result:)
            when "memory_search"
              {
                "tool_name" => tool_name,
                "content" => "Found #{tool_result.fetch("matches").size} memory matches for #{tool_result.fetch("query")}.",
                "query" => tool_result.fetch("query"),
                "matches" => tool_result.fetch("matches"),
              }
            when "memory_list"
              {
                "tool_name" => tool_name,
                "content" => "Listed #{tool_result.fetch("entries").size} memory entries.",
                "scope" => tool_result.fetch("scope"),
                "entries" => tool_result.fetch("entries"),
              }
            when "memory_store", "memory_append_daily"
              {
                "tool_name" => tool_name,
                "content" => "Stored memory at #{tool_result.fetch("memory_path")}.",
                "scope" => tool_result.fetch("scope"),
                "memory_path" => tool_result.fetch("memory_path"),
                "bytes_written" => tool_result.fetch("bytes_written"),
              }
            when "memory_compact_summary"
              {
                "tool_name" => tool_name,
                "content" => "Updated #{tool_result.fetch("scope")} summary at #{tool_result.fetch("memory_path")}.",
                "scope" => tool_result.fetch("scope"),
                "memory_path" => tool_result.fetch("memory_path"),
                "bytes_written" => tool_result.fetch("bytes_written"),
              }
            else
              raise ArgumentError, "unsupported memory projection #{tool_name}"
            end
          end

          private

          def project_memory_get(tool_name:, tool_result:)
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
        end
      end
    end
  end
end
