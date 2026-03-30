module Fenix
  module Operator
    class Snapshot
      WORKSPACE_HIGHLIGHT_LIMIT = 20

      def self.call(...)
        new(...).call
      end

      def initialize(workspace_root:, conversation_id:)
        @layout = Fenix::Workspace::Layout.new(workspace_root:, conversation_id:)
        @memory_store = Fenix::Memory::Store.new(workspace_root:, conversation_id:)
      end

      def call
        snapshot = {
          "workspace" => workspace_section,
          "memory" => memory_section,
          "command_runs" => Fenix::Runtime::CommandRunRegistry.list,
          "process_runs" => Fenix::Processes::Manager.list,
          "browser_sessions" => Fenix::Browser::SessionManager.list,
        }

        path = @layout.conversation_operator_state_file
        FileUtils.mkdir_p(path.dirname)
        path.write(JSON.pretty_generate(snapshot) + "\n")
        snapshot
      end

      private

      def workspace_section
        entries = @layout.workspace_root.glob("*", File::FNM_DOTMATCH)
          .reject { |path| %w[. .. .fenix].include?(path.basename.to_s) }
          .sort_by(&:to_s)
          .first(WORKSPACE_HIGHLIGHT_LIMIT)
          .map do |path|
            {
              "path" => path.relative_path_from(@layout.workspace_root).to_s,
              "node_type" => path.directory? ? "directory" : "file",
            }
          end

        {
          "workspace_root" => @layout.workspace_root.to_s,
          "highlights" => entries,
        }
      end

      def memory_section
        {
          "root_memory_path" => relative_path(@memory_store.root_memory_path),
          "conversation_summary_path" => relative_path(@memory_store.conversation_summary_path),
          "conversation_memory_path" => relative_path(@memory_store.conversation_memory_path),
          "entries" => @memory_store.list_entries(scope: "all"),
        }.compact
      end

      def relative_path(path)
        return if path.blank?

        path.relative_path_from(@layout.workspace_root).to_s
      end
    end
  end
end
