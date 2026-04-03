module Fenix
  module Runtime
    class SystemToolRegistry
      class << self
        def fetch!(tool_name)
          REGISTRY.fetch(tool_name.to_s) do
            raise ArgumentError, "unsupported tool #{tool_name}"
          end
        end

        def supported_tool_names
          REGISTRY.keys
        end

        def registry_backed_tool_names
          REGISTRY.filter_map do |tool_name, entry|
            tool_name if entry.fetch(:registry_backed)
          end
        end

        private

        def register!(entries, tool_names, executor:, projector:, registry_backed: false)
          Array(tool_names).each do |tool_name|
            raise ArgumentError, "duplicate tool registry entry #{tool_name}" if entries.key?(tool_name)

            entries[tool_name] = {
              executor: executor,
              projector: projector,
              registry_backed: registry_backed,
            }.freeze
          end
        end
      end

      entries = {}
      register!(entries, %w[calculator],
        executor: Fenix::Runtime::ToolExecutors::Calculator,
        projector: Fenix::Hooks::ToolResultProjectors::Calculator)
      register!(entries, %w[command_run_list command_run_read_output command_run_terminate command_run_wait exec_command write_stdin],
        executor: Fenix::Runtime::ToolExecutors::ExecCommand,
        projector: Fenix::Hooks::ToolResultProjectors::ExecCommand,
        registry_backed: true)
      register!(entries, %w[process_exec process_list process_proxy_info process_read_output],
        executor: Fenix::Runtime::ToolExecutors::Process,
        projector: Fenix::Hooks::ToolResultProjectors::Process,
        registry_backed: true)
      register!(entries, %w[browser_close browser_get_content browser_list browser_navigate browser_open browser_screenshot browser_session_info],
        executor: Fenix::Runtime::ToolExecutors::Browser,
        projector: Fenix::Hooks::ToolResultProjectors::Browser,
        registry_backed: true)
      register!(entries, %w[workspace_find workspace_read workspace_stat workspace_tree workspace_write],
        executor: Fenix::Runtime::ToolExecutors::Workspace,
        projector: Fenix::Hooks::ToolResultProjectors::Workspace)
      register!(entries, %w[memory_append_daily memory_compact_summary memory_get memory_list memory_search memory_store],
        executor: Fenix::Runtime::ToolExecutors::Memory,
        projector: Fenix::Hooks::ToolResultProjectors::Memory)
      register!(entries, %w[firecrawl_scrape firecrawl_search web_fetch web_search],
        executor: Fenix::Runtime::ToolExecutors::Web,
        projector: Fenix::Hooks::ToolResultProjectors::Web)

      REGISTRY = entries.freeze
      private_constant :REGISTRY
    end
  end
end
