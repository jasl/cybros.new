module Fenix
  module Hooks
    module ToolResultProjectors
      module Browser
        class << self
          def call(tool_name:, tool_result:)
            case tool_name
            when "browser_open"
              {
                "tool_name" => tool_name,
                "content" => "Browser session #{tool_result.fetch("browser_session_id")} opened at #{tool_result.fetch("current_url")}.",
                "browser_session_id" => tool_result.fetch("browser_session_id"),
                "current_url" => tool_result.fetch("current_url"),
              }
            when "browser_list"
              {
                "tool_name" => tool_name,
                "content" => "Listed #{tool_result.fetch("entries").size} browser sessions.",
                "entries" => tool_result.fetch("entries"),
              }
            when "browser_navigate"
              {
                "tool_name" => tool_name,
                "content" => "Browser session navigated to #{tool_result.fetch("current_url")}.",
                "browser_session_id" => tool_result.fetch("browser_session_id"),
                "current_url" => tool_result.fetch("current_url"),
              }
            when "browser_get_content"
              {
                "tool_name" => tool_name,
                "content" => tool_result.fetch("content"),
                "browser_session_id" => tool_result.fetch("browser_session_id"),
                "current_url" => tool_result.fetch("current_url"),
              }
            when "browser_screenshot"
              {
                "tool_name" => tool_name,
                "content" => "Captured screenshot for browser session #{tool_result.fetch("browser_session_id")}.",
                "browser_session_id" => tool_result.fetch("browser_session_id"),
                "current_url" => tool_result.fetch("current_url"),
                "mime_type" => tool_result.fetch("mime_type"),
                "image_base64" => tool_result.fetch("image_base64"),
              }
            when "browser_close"
              {
                "tool_name" => tool_name,
                "content" => "Browser session #{tool_result.fetch("browser_session_id")} closed.",
                "browser_session_id" => tool_result.fetch("browser_session_id"),
                "closed" => tool_result.fetch("closed"),
              }
            when "browser_session_info"
              {
                "tool_name" => tool_name,
                "content" => "Browser session #{tool_result.fetch("browser_session_id")} is at #{tool_result.fetch("current_url")}.",
                "browser_session_id" => tool_result.fetch("browser_session_id"),
                "current_url" => tool_result["current_url"],
              }.compact
            else
              raise ArgumentError, "unsupported browser projection #{tool_name}"
            end
          end
        end
      end
    end
  end
end
