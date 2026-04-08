module Fenix
  module Workspace
    class Layout
      def self.default_root
        ENV.fetch("FENIX_WORKSPACE_ROOT") do
          Rails.env.production? ? "/workspace" : Rails.root.join("tmp", "workspace").to_s
        end
      end

      attr_reader :workspace_root, :conversation_id, :agent_program_version_id

      def initialize(workspace_root:, conversation_id: nil, agent_program_version_id: nil)
        @workspace_root = Pathname.new(workspace_root)
        @conversation_id = conversation_id
        @agent_program_version_id = agent_program_version_id
      end

      def fenix_root
        workspace_root.join(".fenix")
      end

      def program_version_root
        return fenix_root unless agent_program_version_id.present?

        fenix_root.join("agent_program_versions", agent_program_version_id)
      end

      def memory_root
        program_version_root.join("memory")
      end

      def root_memory_file
        memory_root.join("root.md")
      end

      def daily_memory_root
        memory_root.join("daily")
      end

      def conversation_root
        return unless conversation_id.present?

        program_version_root.join("conversations", conversation_id)
      end

      def conversation_meta_file
        conversation_root&.join("meta.json")
      end

      def conversation_context_root
        conversation_root&.join("context")
      end

      def conversation_summary_file
        conversation_context_root&.join("summary.md")
      end

      def conversation_memory_file
        conversation_context_root&.join("memory.md")
      end

      def conversation_operator_state_file
        conversation_context_root&.join("operator_state.json")
      end
    end
  end
end
