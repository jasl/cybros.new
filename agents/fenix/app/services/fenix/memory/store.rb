module Fenix
  module Memory
    class Store
      def initialize(workspace_root:, conversation_id:)
        @workspace_root = Pathname.new(workspace_root).expand_path
        @conversation_id = conversation_id.to_s
      end

      def root_memory_path
        @workspace_root.join("MEMORY.md")
      end

      def root_memory
        read_if_exists(root_memory_path)
      end

      def conversation_summary_path
        @workspace_root.join(".fenix", "conversations", @conversation_id, "context", "summary.md")
      end

      def conversation_summary
        read_if_exists(conversation_summary_path)
      end

      def summary_payload
        root = root_memory
        summary = conversation_summary
        combined = [root.presence, summary.presence].compact.join("\n\n")

        {
          "root_memory" => root,
          "conversation_summary" => summary,
          "summary" => combined.presence,
        }.compact
      end

      private

      def read_if_exists(path)
        return "" unless path.exist?

        path.read
      end
    end
  end
end
