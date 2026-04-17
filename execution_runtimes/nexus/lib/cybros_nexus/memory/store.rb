require "digest"
require "fileutils"

module CybrosNexus
  module Memory
    class Store
      InvalidPathError = Class.new(StandardError)

      def initialize(workspace_root:, conversation_id:, home_root: default_home_root)
        @workspace_root = File.expand_path(workspace_root.to_s)
        @conversation_id = conversation_id.to_s
        @home_root = File.expand_path(home_root.to_s)
      end

      def write(relative_path, content)
        target_path = resolve_session_path(relative_path)
        FileUtils.mkdir_p(File.dirname(target_path))
        File.write(target_path, content)

        {
          "relative_path" => relative_path.to_s,
          "path" => target_path,
          "content" => content,
        }
      end

      def root_memory_path
        File.join(@workspace_root, "MEMORY.md")
      end

      def root_memory
        read_if_exists(root_memory_path)
      end

      def session_summary_path
        File.join(session_context_root, "summary.md")
      end

      def session_summary
        read_if_exists(session_summary_path)
      end

      def summary_payload
        root = root_memory
        summary = session_summary
        combined = [present_string(root), present_string(summary)].compact.join("\n\n")

        payload = {
          "root_memory" => root,
          "session_summary" => summary,
        }
        payload["summary"] = combined unless combined.empty?
        payload
      end

      private

      def default_home_root
        ENV["NEXUS_HOME_ROOT"] || File.join(Dir.home, ".nexus")
      end

      def session_context_root
        File.join(
          @home_root,
          "memory",
          workspace_scope_key,
          "conversations",
          @conversation_id,
          "context"
        )
      end

      def workspace_scope_key
        @workspace_scope_key ||= Digest::SHA256.hexdigest(@workspace_root)[0, 16]
      end

      def resolve_session_path(relative_path)
        path = relative_path.to_s
        raise InvalidPathError, "relative_path is required" if path.empty?

        session_root = File.expand_path(session_context_root)
        target_path = File.expand_path(path, session_root)
        return target_path if target_path == session_root || target_path.start_with?("#{session_root}/")

        raise InvalidPathError, "#{relative_path} escapes the session memory root"
      end

      def read_if_exists(path)
        File.file?(path) ? File.read(path) : ""
      end

      def present_string(value)
        string = value.to_s
        string.empty? ? nil : string
      end
    end
  end
end
