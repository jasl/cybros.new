module Fenix
  module Plugins
    module System
      module Browser
        class Runtime
          ValidationError = Class.new(StandardError)

          def self.call(...)
            new(...).call
          end

          def initialize(tool_call:)
            @tool_call = tool_call.deep_stringify_keys
          end

          def call
            case @tool_call.fetch("tool_name")
            when "browser_open"
              Fenix::Browser::SessionManager.call(action: "open", url: @tool_call.dig("arguments", "url"))
            when "browser_navigate"
              Fenix::Browser::SessionManager.call(
                action: "navigate",
                browser_session_id: @tool_call.dig("arguments", "browser_session_id"),
                url: @tool_call.dig("arguments", "url")
              )
            when "browser_get_content"
              Fenix::Browser::SessionManager.call(
                action: "get_content",
                browser_session_id: @tool_call.dig("arguments", "browser_session_id")
              )
            when "browser_screenshot"
              Fenix::Browser::SessionManager.call(
                action: "screenshot",
                browser_session_id: @tool_call.dig("arguments", "browser_session_id"),
                full_page: @tool_call.dig("arguments", "full_page") != false
              )
            when "browser_close"
              Fenix::Browser::SessionManager.call(
                action: "close",
                browser_session_id: @tool_call.dig("arguments", "browser_session_id")
              )
            else
              raise ArgumentError, "unsupported browser runtime tool #{@tool_call.fetch("tool_name")}"
            end
          rescue Fenix::Browser::SessionManager::ValidationError => error
            raise ValidationError, error.message
          end
        end
      end
    end
  end
end
