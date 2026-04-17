module CybrosNexus
  module Tools
    class ExecCommand
      ValidationError = Class.new(StandardError)

      def initialize(command_host:, runtime_owner_id:, workdir:, environment: {})
        @command_host = command_host
        @runtime_owner_id = runtime_owner_id
        @workdir = workdir
        @environment = environment
      end

      def call(tool_name:, arguments:, resource_ref: nil)
        case tool_name
        when "exec_command"
          @command_host.start(
            command_run_id: resource_ref.fetch("command_run_id"),
            runtime_owner_id: @runtime_owner_id,
            command_line: arguments.fetch("command_line"),
            pty: arguments["pty"] == true,
            workdir: @workdir,
            environment: @environment
          )
        when "write_stdin"
          @command_host.write_stdin(
            command_run_id: arguments.fetch("command_run_id"),
            runtime_owner_id: @runtime_owner_id,
            text: arguments["text"],
            eof: arguments["eof"] == true,
            wait_for_exit: arguments["wait_for_exit"] == true,
            timeout_seconds: arguments.fetch("timeout_seconds", 30)
          )
        when "command_run_read_output"
          @command_host.read_output(
            command_run_id: arguments.fetch("command_run_id"),
            runtime_owner_id: @runtime_owner_id
          )
        when "command_run_wait"
          @command_host.wait(
            command_run_id: arguments.fetch("command_run_id"),
            runtime_owner_id: @runtime_owner_id,
            timeout_seconds: arguments.fetch("timeout_seconds", 30)
          )
        when "command_run_list"
          {
            "entries" => @command_host.list(runtime_owner_id: @runtime_owner_id),
          }
        when "command_run_terminate"
          @command_host.terminate(
            command_run_id: arguments.fetch("command_run_id"),
            runtime_owner_id: @runtime_owner_id
          )
        else
          raise ValidationError, "unsupported exec command tool #{tool_name}"
        end
      rescue KeyError => error
        raise ValidationError, error.message
      rescue CybrosNexus::Resources::CommandHost::ValidationError => error
        raise ValidationError, error.message
      end
    end
  end
end
