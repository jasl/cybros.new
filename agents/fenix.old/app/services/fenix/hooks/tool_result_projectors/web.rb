module Fenix
  module Hooks
    module ToolResultProjectors
      module Web
        class << self
          def call(tool_name:, tool_result:)
            case tool_name
            when "web_search", "firecrawl_search"
              project_search_results(tool_name:, tool_result:)
            when "firecrawl_scrape"
              markdown = tool_result.fetch("markdown")

              {
                "tool_name" => tool_name,
                "content" => markdown,
                "url" => tool_result.fetch("url"),
                "markdown" => markdown,
                "metadata" => tool_result.fetch("metadata"),
              }
            when "web_fetch"
              {
                "tool_name" => tool_name,
                "content" => tool_result.fetch("content"),
                "url" => tool_result.fetch("url"),
                "content_type" => tool_result.fetch("content_type"),
                "redirects" => tool_result.fetch("redirects"),
              }
            else
              raise ArgumentError, "unsupported web projection #{tool_name}"
            end
          end

          private

          def project_search_results(tool_name:, tool_result:)
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
        end
      end
    end
  end
end
