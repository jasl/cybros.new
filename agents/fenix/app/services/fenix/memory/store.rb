module Fenix
  module Memory
    class Store
      attr_reader :layout

      def initialize(workspace_root:, conversation_id:)
        @layout = Fenix::Workspace::Layout.new(workspace_root:, conversation_id:)
      end

      def root_memory
        workspace_memory_override || fenix_root_memory
      end

      def conversation_summary
        return "" unless layout.conversation_summary_file&.exist?

        layout.conversation_summary_file.read
      end

      def daily_memory_root
        layout.daily_memory_root
      end

      private

      def workspace_memory_override
        path = layout.workspace_root.join("MEMORY.md")
        path.read if path.exist?
      end

      def fenix_root_memory
        return "" unless layout.root_memory_file.exist?

        layout.root_memory_file.read
      end
    end
  end
end
