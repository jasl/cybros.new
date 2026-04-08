module Fenix
  module Prompts
    class WorkspaceInstructionLoader
      def self.call(...)
        new(...).call
      end

      def initialize(workspace_root:)
        @workspace_root = Pathname.new(workspace_root).expand_path
      end

      def call
        instructions_path.read if instructions_path.exist?
      end

      private

      def instructions_path
        @workspace_root.join("AGENTS.md")
      end
    end
  end
end
