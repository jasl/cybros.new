module Fenix
  module Runtime
    module ToolExecutors
      module Browser
        class << self
          def call(tool_call:, current_runtime_owner_id:, **)
            new_runtime(
              tool_call: tool_call,
              current_runtime_owner_id: current_runtime_owner_id
            ).call
          end

          private

          def new_runtime(...)
            Runtime.new(...)
          end
        end

        class Runtime
          def initialize(tool_call:, current_runtime_owner_id:)
            @tool_call = tool_call.deep_stringify_keys
            @current_runtime_owner_id = current_runtime_owner_id
          end

          def call
            arguments = @tool_call.fetch("arguments", {}).deep_stringify_keys

            case @tool_call.fetch("tool_name")
            when "browser_open"
              session_manager.call(
                action: "open",
                url: arguments["url"],
                runtime_owner_id: @current_runtime_owner_id
              )
            when "browser_navigate"
              session_manager.call(
                action: "navigate",
                browser_session_id: arguments["browser_session_id"],
                url: arguments["url"],
                runtime_owner_id: @current_runtime_owner_id
              )
            when "browser_get_content"
              session_manager.call(
                action: "get_content",
                browser_session_id: arguments["browser_session_id"],
                runtime_owner_id: @current_runtime_owner_id
              )
            when "browser_screenshot"
              session_manager.call(
                action: "screenshot",
                browser_session_id: arguments["browser_session_id"],
                full_page: arguments.key?("full_page") ? arguments["full_page"] : true,
                runtime_owner_id: @current_runtime_owner_id
              )
            when "browser_list"
              session_manager.call(
                action: "list",
                runtime_owner_id: @current_runtime_owner_id
              )
            when "browser_close"
              session_manager.call(
                action: "close",
                browser_session_id: arguments["browser_session_id"],
                runtime_owner_id: @current_runtime_owner_id
              )
            when "browser_session_info"
              session_manager.call(
                action: "info",
                browser_session_id: arguments["browser_session_id"],
                runtime_owner_id: @current_runtime_owner_id
              )
            else
              raise Fenix::Browser::SessionManager::ValidationError, "unsupported browser tool #{@tool_call.fetch("tool_name")}"
            end
          end

          private

          def session_manager
            Fenix::Browser::SessionManager
          end
        end
      end
    end
  end
end
