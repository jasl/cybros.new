module Fenix
  module Hooks
    module ToolResultProjectors
      module Workspace
        class << self
          def call(tool_name:, tool_result:)
            case tool_name
            when "workspace_read"
              {
                "tool_name" => tool_name,
                "content" => "Workspace file #{tool_result.fetch("path")}:\n#{tool_result.fetch("content")}",
                "path" => tool_result.fetch("path"),
                "file_content" => tool_result.fetch("content"),
                "bytes_read" => tool_result.fetch("bytes_read"),
              }
            when "workspace_write"
              {
                "tool_name" => tool_name,
                "content" => "Wrote #{tool_result.fetch("bytes_written")} bytes to workspace file #{tool_result.fetch("path")}.",
                "path" => tool_result.fetch("path"),
                "bytes_written" => tool_result.fetch("bytes_written"),
              }
            when "workspace_tree"
              {
                "tool_name" => tool_name,
                "content" => "Listed #{tool_result.fetch("entries").size} workspace entries under #{tool_result.fetch("path")}.",
                "path" => tool_result.fetch("path"),
                "entries" => tool_result.fetch("entries"),
              }
            when "workspace_stat"
              {
                "tool_name" => tool_name,
                "content" => "Workspace path #{tool_result.fetch("path")} is a #{tool_result.fetch("node_type")}.",
                "path" => tool_result.fetch("path"),
                "node_type" => tool_result.fetch("node_type"),
                "size_bytes" => tool_result.fetch("size_bytes"),
              }
            when "workspace_find"
              {
                "tool_name" => tool_name,
                "content" => "Found #{tool_result.fetch("matches").size} workspace paths matching #{tool_result.fetch("query")}.",
                "path" => tool_result.fetch("path"),
                "query" => tool_result.fetch("query"),
                "matches" => tool_result.fetch("matches"),
              }
            else
              raise ArgumentError, "unsupported workspace projection #{tool_name}"
            end
          end
        end
      end
    end
  end
end
