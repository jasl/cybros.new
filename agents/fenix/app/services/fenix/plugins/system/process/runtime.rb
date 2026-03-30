module Fenix
  module Plugins
    module System
      module Process
        class Runtime
          ValidationError = Class.new(StandardError)

          def self.call(...)
            new(...).call
          end

          def initialize(tool_call:, process_run:, control_client: nil, launcher: Fenix::Processes::Launcher)
            @tool_call = tool_call.deep_stringify_keys
            @process_run = process_run.deep_stringify_keys
            @control_client = control_client
            @launcher = launcher
          end

          def call
            raise ValidationError, "unsupported process runtime tool #{@tool_call.fetch("tool_name")}" unless @tool_call.fetch("tool_name") == "process_exec"

            @launcher.call(
              process_run: @process_run,
              command_line: @tool_call.dig("arguments", "command_line"),
              proxy_port: @tool_call.dig("arguments", "proxy_port"),
              control_client: @control_client
            )
          end
        end
      end
    end
  end
end
