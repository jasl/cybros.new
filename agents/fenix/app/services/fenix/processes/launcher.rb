module Fenix
  module Processes
    class Launcher
      def self.call(...)
        new(...).call
      end

      def initialize(process_run:, command_line:, proxy_port: nil, control_client: nil, manager: Fenix::Processes::Manager, proxy_registry: Fenix::Processes::ProxyRegistry)
        @process_run = process_run.deep_stringify_keys
        @command_line = command_line
        @proxy_port = proxy_port
        @control_client = control_client
        @manager = manager
        @proxy_registry = proxy_registry
      end

      def call
        @manager.spawn!(
          process_run_id: @process_run.fetch("process_run_id"),
          command_line: @command_line,
          control_client: @control_client
        )

        proxy_entry =
          if @proxy_port.present?
            @proxy_registry.register(
              process_run_id: @process_run.fetch("process_run_id"),
              target_port: @proxy_port
            )
          end

        {
          "process_run_id" => @process_run.fetch("process_run_id"),
          "lifecycle_state" => "running",
          "proxy_path" => proxy_entry&.fetch("path_prefix"),
          "proxy_target_url" => proxy_entry&.fetch("target_url"),
        }.compact
      end
    end
  end
end
