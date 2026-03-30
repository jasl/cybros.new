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
            when "workspace_read"
              workspace_read
            when "workspace_write"
              workspace_write
            else
              raise ArgumentError, "unsupported workspace runtime tool #{@tool_call.fetch("tool_name")}"
            end
          end

          private

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

          def resolve_workspace_path!(raw_path)
            candidate = Pathname.new(raw_path.to_s)
            raise ValidationError, "workspace path must be present" if raw_path.to_s.blank?
            raise ValidationError, "workspace path must be relative" if candidate.absolute?

            resolved = @workspace_root.join(candidate).cleanpath
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

          def relative_path(path)
            path.relative_path_from(@workspace_root).to_s
          end
        end
      end
    end
  end
end
