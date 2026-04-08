module Fenix
  module Plugins
    module System
      module Process
        class Runtime
          ValidationError = Class.new(StandardError)

          def self.call(...)
            new(...).call
          end

          def initialize(tool_call:, process_run:, control_client: nil, launcher: Fenix::Processes::Launcher, current_agent_task_run_id:)
            @tool_call = tool_call.deep_stringify_keys
            @process_run = process_run&.deep_stringify_keys
            @control_client = control_client
            @launcher = launcher
            @current_agent_task_run_id = current_agent_task_run_id
          end

          def call
            case @tool_call.fetch("tool_name")
            when "process_exec"
              @launcher.call(
                process_run: @process_run,
                command_line: @tool_call.dig("arguments", "command_line"),
                proxy_port: @tool_call.dig("arguments", "proxy_port"),
                control_client: @control_client
              )
            when "process_list"
              { "entries" => Fenix::Processes::Manager.list(agent_task_run_id: @current_agent_task_run_id) }
            when "process_proxy_info"
              lookup_owned_process_run!

              Fenix::Processes::Manager.proxy_info(process_run_id: @tool_call.dig("arguments", "process_run_id")) || {
                "process_run_id" => @tool_call.dig("arguments", "process_run_id"),
                "proxy_path" => nil,
                "proxy_target_url" => nil,
              }
            when "process_read_output"
              snapshot = Fenix::Processes::Manager.output_snapshot(process_run_id: @tool_call.dig("arguments", "process_run_id"))
              raise ValidationError, "unknown process run #{@tool_call.dig("arguments", "process_run_id")}" if snapshot.blank?
              raise ValidationError, "process run #{@tool_call.dig("arguments", "process_run_id")} is not owned by this agent task" unless snapshot["agent_task_run_id"] == @current_agent_task_run_id

              snapshot
            else
              raise ValidationError, "unsupported process runtime tool #{@tool_call.fetch("tool_name")}"
            end
          end

          private

          def lookup_owned_process_run!
            process_run_id = @tool_call.dig("arguments", "process_run_id")
            entry = Fenix::Processes::Manager.lookup(process_run_id:)
            raise ValidationError, "unknown process run #{process_run_id}" if entry.blank?
            raise ValidationError, "process run #{process_run_id} is not owned by this agent task" unless entry.agent_task_run_id == @current_agent_task_run_id

            entry
          end
        end
      end
    end
  end
end
