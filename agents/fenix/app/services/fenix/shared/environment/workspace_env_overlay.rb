module Fenix
  module Shared
    module Environment
      class WorkspaceEnvOverlay
        ValidationError = Class.new(StandardError)

        KEY_PATTERN = /\A[A-Z][A-Z0-9_]*\z/.freeze
        RESERVED_PREFIXES = [
          "CORE_MATRIX_",
          "ACTIVE_RECORD_ENCRYPTION__",
        ].freeze
        RESERVED_KEYS = %w[
          SECRET_KEY_BASE
          RAILS_ENV
          DATABASE_URL
          BUNDLE_GEMFILE
          BUNDLE_PATH
          FENIX_HOME_ROOT
          FENIX_PYTHON_ROOT
          FENIX_PYTHON_INSTALL_ROOT
          UV_PYTHON_INSTALL_DIR
          PLAYWRIGHT_BROWSERS_PATH
          PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
          PATH
        ].freeze

        def self.call(...)
          new(...).call
        end

        def initialize(workspace_root:)
          @workspace_root = Pathname.new(workspace_root).expand_path
        end

        def call
          return {} unless overlay_path.file?

          overlay_path.each_line.with_index(1).each_with_object({}) do |(line, line_number), overlay|
            stripped = line.strip
            next if stripped.blank? || stripped.start_with?("#")

            key, value = parse_assignment!(stripped, line_number: line_number)
            reject_reserved_key!(key, line_number: line_number)
            overlay[key] = value
          end
        end

        private

        def overlay_path
          @overlay_path ||= @workspace_root.join(".fenix", "workspace.env")
        end

        def parse_assignment!(line, line_number:)
          normalized = line.sub(/\Aexport\s+/, "")
          key, value = normalized.split("=", 2)

          if key.blank? || value.nil?
            raise ValidationError, "invalid workspace env line #{line_number}: #{line}"
          end

          unless key.match?(KEY_PATTERN)
            raise ValidationError, "invalid workspace env key #{key.inspect} on line #{line_number}"
          end

          [key, value]
        end

        def reject_reserved_key!(key, line_number:)
          return unless RESERVED_KEYS.include?(key) || RESERVED_PREFIXES.any? { |prefix| key.start_with?(prefix) }

          raise ValidationError, "reserved workspace env key #{key} on line #{line_number}"
        end
      end
    end
  end
end
