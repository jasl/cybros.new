module Fenix
  module Plugins
    module System
      module Memory
        class Runtime
          ValidationError = Class.new(StandardError)

          def self.call(...)
            new(...).call
          end

          def initialize(tool_call:, workspace_root:, conversation_id:)
            @tool_call = tool_call.deep_stringify_keys
            @layout = Fenix::Workspace::Layout.new(workspace_root:, conversation_id:)
            @memory_repository = Fenix::Memory::Store.new(workspace_root:, conversation_id:)
          end

          def call
            case @tool_call.fetch("tool_name")
            when "memory_get"
              memory_get
            when "memory_search"
              memory_search
            when "memory_store"
              memory_store
            else
              raise ArgumentError, "unsupported memory runtime tool #{@tool_call.fetch("tool_name")}"
            end
          end

          private

          attr_reader :layout, :memory_repository

          def memory_get
            scope = @tool_call.dig("arguments", "scope").presence || "all"

            case scope
            when "all"
              {
                "scope" => scope,
                "root_memory" => memory_repository.root_memory,
                "conversation_summary" => memory_repository.conversation_summary,
                "conversation_memory" => memory_repository.conversation_memory,
              }
            when "root"
              {
                "scope" => scope,
                "root_memory" => memory_repository.root_memory,
              }
            when "conversation"
              {
                "scope" => scope,
                "conversation_summary" => memory_repository.conversation_summary,
                "conversation_memory" => memory_repository.conversation_memory,
              }
            else
              raise ValidationError, "unsupported memory_get scope #{scope}"
            end
          end

          def memory_search
            query = @tool_call.dig("arguments", "query").to_s.strip
            limit = [@tool_call.dig("arguments", "limit").to_i, 1].max
            raise ValidationError, "memory_search query must be present" if query.blank?

            matches = search_source_paths.filter_map do |path|
              content = path.read
              next unless content.downcase.include?(query.downcase)

              {
                "path" => relative_path(path),
                "excerpt" => excerpt_for(content, query),
              }
            end.first(limit)

            {
              "query" => query,
              "matches" => matches,
            }
          end

          def memory_store
            text = @tool_call.dig("arguments", "text").to_s
            title = @tool_call.dig("arguments", "title").to_s
            scope = @tool_call.dig("arguments", "scope").presence || "daily"
            raise ValidationError, "memory_store text must be present" if text.blank?

            path =
              case scope
              when "daily"
                next_daily_memory_path(title:)
              when "conversation"
                layout.conversation_memory_file
              when "root"
                layout.root_memory_file
              else
                raise ValidationError, "unsupported memory_store scope #{scope}"
              end

            FileUtils.mkdir_p(path.dirname)
            path.write(text)

            {
              "scope" => scope,
              "memory_path" => relative_path(path),
              "bytes_written" => text.bytesize,
            }
          end

          def search_source_paths
            root_path = layout.workspace_root.join("MEMORY.md")
            sources = []
            sources << root_path if root_path.file?
            sources << layout.root_memory_file if layout.root_memory_file.file? && !root_path.file?
            sources << layout.conversation_summary_file if layout.conversation_summary_file&.file?
            sources << layout.conversation_memory_file if layout.conversation_memory_file&.file?
            sources.concat(layout.daily_memory_root.glob("**/*").select(&:file?))
            sources
          end

          def excerpt_for(content, query)
            line = content.lines.find { |entry| entry.downcase.include?(query.downcase) }
            return line.to_s.strip if line.present?

            match_index = content.downcase.index(query.downcase) || 0
            content[[match_index - 40, 0].max, query.length + 80].to_s.strip
          end

          def next_daily_memory_path(title:)
            slug = title.parameterize.presence || "memory"
            timestamp = Time.current.utc.strftime("%Y%m%dT%H%M%S")
            layout.daily_memory_root.join("#{timestamp}-#{slug}-#{SecureRandom.hex(4)}.md")
          end

          def relative_path(path)
            path.relative_path_from(layout.workspace_root).to_s
          end
        end
      end
    end
  end
end
