require "fileutils"
require "json"

module CoreMatrixCLI
  module CredentialStores
    class FileStore
      DEFAULT_FILENAME = "credentials.json"

      def self.default_path
        overridden_path = ENV["CORE_MATRIX_CLI_CREDENTIAL_PATH"].to_s.strip
        return overridden_path unless overridden_path.empty?

        File.join(Dir.home, ".config", "core_matrix_cli", DEFAULT_FILENAME)
      end

      def initialize(path: self.class.default_path)
        @path = path
      end

      attr_reader :path

      def read
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      end

      def write(values)
        payload = JSON.generate(stringify_keys(values))

        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
          file.write(payload)
        end
        File.chmod(0o600, path)
      end

      def clear
        File.delete(path) if File.exist?(path)
      end

      private

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), result|
            result[key.to_s] = stringify_keys(nested_value)
          end
        when Array
          value.map { |nested_value| stringify_keys(nested_value) }
        else
          value
        end
      end
    end
  end
end
