module Fenix
  module Workspace
    class EnvOverlay
      def self.call(...)
        new(...).call
      end

      def initialize(workspace_root:, conversation_id:, agent_program_version_id: nil)
        @layout = Layout.new(workspace_root:, conversation_id:, agent_program_version_id:)
      end

      def call
        env_paths.each_with_object({}) do |path, overlay|
          next unless path.exist?

          overlay.merge!(parse_env_file(path))
        end
      end

      private

      attr_reader :layout

      def env_paths
        paths = [
          layout.workspace_root.join(".env"),
          layout.workspace_root.join(".env.agent"),
        ]
        if layout.agent_program_version_id.present?
          paths << layout.program_version_root.join(".env")
          paths << layout.program_version_root.join(".env.agent")
        end
        paths + [
          layout.conversation_root.join(".env"),
          layout.conversation_root.join(".env.agent"),
        ]
      end

      def parse_env_file(path)
        path.each_line.each_with_object({}) do |line, values|
          stripped = line.strip
          next if stripped.blank? || stripped.start_with?("#")

          key, value = stripped.sub(/\Aexport\s+/, "").split("=", 2)
          next if key.blank? || value.nil?

          values[key] = value
        end
      end
    end
  end
end
