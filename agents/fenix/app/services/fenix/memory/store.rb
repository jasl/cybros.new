module Fenix
  module Memory
    class Store
      attr_reader :layout

      def initialize(workspace_root:, conversation_id:, deployment_public_id: nil)
        @layout = Fenix::Workspace::Layout.new(workspace_root:, conversation_id:, deployment_public_id:)
      end

      def root_memory_path
        workspace_memory_override_path || layout.root_memory_file
      end

      def root_memory
        workspace_memory_override || fenix_root_memory
      end

      def conversation_summary_path
        layout.conversation_summary_file
      end

      def conversation_summary
        return "" unless layout.conversation_summary_file&.exist?

        layout.conversation_summary_file.read
      end

      def conversation_memory_path
        layout.conversation_memory_file
      end

      def conversation_memory
        return "" unless layout.conversation_memory_file&.exist?

        layout.conversation_memory_file.read
      end

      def daily_memory_root
        layout.daily_memory_root
      end

      def list_entries(scope: "all")
        entries =
          case scope
          when "all"
            root_memory_entries + conversation_entries + daily_entries
          when "root"
            root_memory_entries
          when "conversation"
            conversation_entries
          when "daily"
            daily_entries
          else
            raise ArgumentError, "unsupported memory list scope #{scope}"
          end

        entries.sort_by { |entry| entry.fetch("path") }
      end

      def store_text(scope:, text:, title: "")
        path =
          case scope
          when "daily"
            next_daily_memory_path(title:)
          when "conversation"
            layout.conversation_memory_file
          when "root"
            layout.root_memory_file
          else
            raise ArgumentError, "unsupported memory store scope #{scope}"
          end

        write_path(path, text)
      end

      def compact_summary(scope:, text:)
        path =
          case scope
          when "conversation"
            layout.conversation_summary_file
          when "root"
            root_memory_path
          else
            raise ArgumentError, "unsupported memory compact scope #{scope}"
          end

        write_path(path, text)
      end

      private

      def root_memory_entries
        return [] unless root_memory_path.exist?

        [entry_for(root_memory_path, "root")]
      end

      def conversation_entries
        [conversation_summary_path, conversation_memory_path].filter_map do |path|
          next unless path&.exist?

          entry_for(path, "conversation")
        end
      end

      def daily_entries
        daily_memory_root.glob("**/*").select(&:file?).map { |path| entry_for(path, "daily") }
      end

      def entry_for(path, scope)
        {
          "scope" => scope,
          "path" => relative_path(path),
          "size_bytes" => path.size,
        }
      end

      def write_path(path, text)
        FileUtils.mkdir_p(path.dirname)
        path.write(text)
        path
      end

      def next_daily_memory_path(title:)
        slug = title.to_s.parameterize.presence || "memory"
        timestamp = Time.current.utc.strftime("%Y%m%dT%H%M%S")
        layout.daily_memory_root.join("#{timestamp}-#{slug}-#{SecureRandom.hex(4)}.md")
      end

      def relative_path(path)
        path.relative_path_from(layout.workspace_root).to_s
      end

      def workspace_memory_override_path
        path = layout.workspace_root.join("MEMORY.md")
        path if path.exist?
      end

      def workspace_memory_override
        workspace_memory_override_path&.read
      end

      def fenix_root_memory
        return "" unless layout.root_memory_file.exist?

        layout.root_memory_file.read
      end
    end
  end
end
