module Fenix
  module Runtime
    module ToolExecutors
      module Process
        class ValidationError < StandardError; end

        class << self
          def call(tool_call:, control_client:, current_runtime_owner_id:, process_run: nil, launcher: Fenix::Processes::Launcher, **)
            Runtime.new(
              tool_call: tool_call,
              process_run: process_run,
              control_client: control_client,
              launcher: launcher,
              current_runtime_owner_id: current_runtime_owner_id
            ).call
          end
        end

        class Runtime
          def initialize(tool_call:, process_run:, control_client:, launcher:, current_runtime_owner_id:)
            @tool_call = tool_call.deep_stringify_keys
            @process_run = process_run&.deep_stringify_keys
            @control_client = control_client
            @launcher = launcher
            @current_runtime_owner_id = current_runtime_owner_id
          end

          def call
            case @tool_call.fetch("tool_name")
            when "process_exec"
              raise ValidationError, "missing process run ref for process_exec" if @process_run.blank?

              @launcher.call(
                process_run: @process_run,
                command_line: @tool_call.dig("arguments", "command_line"),
                proxy_port: @tool_call.dig("arguments", "proxy_port"),
                control_client: @control_client
              )
            when "process_list"
              { "entries" => Fenix::Processes::Manager.list(runtime_owner_id: @current_runtime_owner_id) }
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
              unless snapshot["runtime_owner_id"] == @current_runtime_owner_id
                raise ValidationError, "process run #{@tool_call.dig("arguments", "process_run_id")} is not owned by this execution"
              end

              snapshot
            else
              raise ValidationError, "unsupported process runtime tool #{@tool_call.fetch("tool_name")}"
            end
          end

          private

          def lookup_owned_process_run!
            process_run_id = @tool_call.dig("arguments", "process_run_id")
            entry = Fenix::Processes::Manager.lookup(process_run_id: process_run_id)
            raise ValidationError, "unknown process run #{process_run_id}" if entry.blank?
            raise ValidationError, "process run #{process_run_id} is not owned by this execution" unless entry.runtime_owner_id == @current_runtime_owner_id

            entry
          end
        end
      end
    end
  end
end
