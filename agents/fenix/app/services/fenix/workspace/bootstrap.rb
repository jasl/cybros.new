module Fenix
  module Workspace
    class Bootstrap
      def self.call(...)
        new(...).call
      end

      def initialize(workspace_root:, conversation_id:)
        @layout = Layout.new(workspace_root:, conversation_id:)
      end

      def call
        seed_directories!
        seed_files!
        layout
      end

      private

      attr_reader :layout

      def seed_directories!
        [
          layout.memory_root,
          layout.daily_memory_root,
          layout.conversation_root,
          layout.conversation_context_root,
          layout.conversation_root.join("attachments"),
          layout.conversation_root.join("artifacts"),
          layout.conversation_root.join("runs"),
        ].each do |path|
          FileUtils.mkdir_p(path)
        end
      end

      def seed_files!
        seed_file(layout.root_memory_file, "# Fenix root memory\n")
        seed_file(layout.conversation_summary_file, "")
        seed_metadata_file
      end

      def seed_metadata_file
        return if layout.conversation_meta_file.exist?

        payload = {
          "conversation_public_id" => layout.conversation_id,
          "workspace_root" => layout.workspace_root.to_s,
        }
        layout.conversation_meta_file.write(JSON.pretty_generate(payload) + "\n")
      end

      def seed_file(path, contents)
        return if path.exist?

        path.write(contents)
      end
    end
  end
end
