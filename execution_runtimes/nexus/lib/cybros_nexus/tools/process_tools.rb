module CybrosNexus
  module Tools
    class ProcessTools
      ValidationError = Class.new(StandardError)

      def initialize(process_host:, runtime_owner_id:, workdir:, environment: {})
        @process_host = process_host
        @runtime_owner_id = runtime_owner_id
        @workdir = workdir
        @environment = environment
      end

      def call(tool_name:, arguments:, resource_ref: nil)
        case tool_name
        when "process_exec"
          @process_host.start(
            process_run_id: resource_ref.fetch("process_run_id"),
            runtime_owner_id: @runtime_owner_id,
            command_line: arguments.fetch("command_line"),
            workdir: @workdir,
            environment: @environment,
            proxy_port: arguments["proxy_port"]
          )
        when "process_list"
          {
            "entries" => @process_host.list(runtime_owner_id: @runtime_owner_id),
          }
        when "process_proxy_info"
          @process_host.proxy_info(process_run_id: arguments.fetch("process_run_id")) || {
            "process_run_id" => arguments.fetch("process_run_id"),
            "proxy_path" => nil,
            "proxy_target_url" => nil,
          }
        when "process_read_output"
          @process_host.read_output(
            process_run_id: arguments.fetch("process_run_id"),
            runtime_owner_id: @runtime_owner_id
          )
        else
          raise ValidationError, "unsupported process runtime tool #{tool_name}"
        end
      rescue KeyError => error
        raise ValidationError, error.message
      rescue CybrosNexus::Resources::ProcessHost::ValidationError => error
        raise ValidationError, error.message
      end
    end
  end
end
