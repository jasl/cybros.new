module Fenix
  module Plugins
    module System
      module Workspace
        class Runtime
          ValidationError = Class.new(StandardError)

          def self.call(...)
            new(...).call
          end

          def initialize(tool_call:, workspace_root:)
            @tool_call = tool_call.deep_stringify_keys
            @workspace_root = Pathname.new(workspace_root).cleanpath
          end

          def call
            case @tool_call.fetch("tool_name")
            when "workspace_find"
              workspace_find
            when "workspace_read"
              workspace_read
            when "workspace_stat"
              workspace_stat
            when "workspace_tree"
              workspace_tree
            when "workspace_write"
              workspace_write
            else
              raise ArgumentError, "unsupported workspace runtime tool #{@tool_call.fetch("tool_name")}"
            end
          end

          private

          def workspace_find
            query = @tool_call.dig("arguments", "query").to_s.strip
            limit = positive_limit(@tool_call.dig("arguments", "limit"), default: 20)
            raise ValidationError, "workspace_find query must be present" if query.blank?

            search_root = resolve_workspace_path_or_root(@tool_call.dig("arguments", "path"))
            raise ValidationError, "workspace path #{relative_path(search_root)} does not exist" unless search_root.exist?

            matches = searchable_paths(search_root).filter_map do |path|
              next unless relative_path(path).downcase.include?(query.downcase)

              workspace_entry(path)
            end.first(limit)

            {
              "path" => relative_path(search_root),
              "query" => query,
              "matches" => matches,
            }
          end

          def workspace_read
            path = resolve_workspace_path!(@tool_call.dig("arguments", "path"))
            raise ValidationError, "workspace path #{relative_path(path)} does not exist" unless path.exist?
            raise ValidationError, "workspace path #{relative_path(path)} is not a file" unless path.file?

            content = path.read
            {
              "path" => relative_path(path),
              "content" => content,
              "bytes_read" => content.bytesize,
            }
          end

          def workspace_stat
            path = resolve_workspace_path_or_root(@tool_call.dig("arguments", "path"))
            raise ValidationError, "workspace path #{relative_path(path)} does not exist" unless path.exist?

            workspace_entry(path)
          end

          def workspace_tree
            path = resolve_workspace_path_or_root(@tool_call.dig("arguments", "path"))
            limit = positive_limit(@tool_call.dig("arguments", "limit"), default: 200)
            raise ValidationError, "workspace path #{relative_path(path)} does not exist" unless path.exist?

            entries =
              if path.file?
                [workspace_entry(path)]
              else
                searchable_paths(path).map { |entry| workspace_entry(entry) }.first(limit)
              end

            {
              "path" => relative_path(path),
              "entries" => entries,
            }
          end

          def workspace_write
            path = resolve_workspace_path!(@tool_call.dig("arguments", "path"))
            content = @tool_call.dig("arguments", "content").to_s

            FileUtils.mkdir_p(path.dirname)
            path.write(content)

            {
              "path" => relative_path(path),
              "bytes_written" => content.bytesize,
            }
          end

          def workspace_entry(path)
            node_type = path.directory? ? "directory" : "file"

            {
              "path" => relative_path(path),
              "node_type" => node_type,
              "size_bytes" => path.file? ? path.size : 0,
            }
          end

          def searchable_paths(path)
            return [path] if path.file?

            path.glob("**/*", File::FNM_DOTMATCH)
              .reject { |entry| dot_entry?(entry) || reserved_runtime_state?(entry) }
              .sort_by(&:to_s)
          end

          def dot_entry?(path)
            %w[. ..].include?(path.basename.to_s)
          end

          def resolve_workspace_path_or_root(raw_path)
            return @workspace_root if raw_path.to_s.blank? || raw_path.to_s == "."

            resolve_workspace_path!(raw_path)
          end

          def resolve_workspace_path!(raw_path)
            candidate = Pathname.new(raw_path.to_s)
            raise ValidationError, "workspace path must be present" if raw_path.to_s.blank?
            resolved =
              if candidate.absolute?
                candidate.cleanpath
              else
                @workspace_root.join(candidate).cleanpath
              end
            workspace_root_prefix = "#{@workspace_root}#{File::SEPARATOR}"
            reserved_root = @workspace_root.join(".fenix").cleanpath
            reserved_root_prefix = "#{reserved_root}#{File::SEPARATOR}"

            unless resolved == @workspace_root || resolved.to_s.start_with?(workspace_root_prefix)
              raise ValidationError, "workspace path #{raw_path} resolves outside the workspace root"
            end

            if resolved == reserved_root || resolved.to_s.start_with?(reserved_root_prefix)
              raise ValidationError, "workspace path #{raw_path} targets reserved .fenix runtime state"
            end

            resolved
          end

          def reserved_runtime_state?(path)
            reserved_root = @workspace_root.join(".fenix").cleanpath
            reserved_root_prefix = "#{reserved_root}#{File::SEPARATOR}"

            path == reserved_root || path.to_s.start_with?(reserved_root_prefix)
          end

          def positive_limit(raw_limit, default:)
            value = raw_limit.to_i
            value.positive? ? value : default
          end

          def relative_path(path)
            path.relative_path_from(@workspace_root).to_s
          end
        end
      end
    end
  end
end
